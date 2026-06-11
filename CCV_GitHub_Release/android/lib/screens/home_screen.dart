import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/clipboard_service.dart';
import '../services/websocket_service.dart';
import '../services/udp_discovery.dart';
import '../services/foreground_service_bridge.dart';
import '../services/permission_service.dart';
import 'setup_wizard_screen.dart';
import '../services/native_clipboard_monitor.dart';
import '../services/accessibility_event_bridge.dart';
import 'accessibility_debug_screen.dart';
import 'clipboard_debug_screen.dart';

/// 主界面
///
/// 用户操作流程：
///   1. 打开 App
///   2. 电脑端也打开，输入同一个房间号
///   3. 手机输入房间号 → 点击「加入房间」
///   4. App 自动 UDP 搜索电脑 → 建立 WebSocket → 开始同步
///
/// 生命周期管理：
///   - 通过 WidgetsBindingObserver 监听 App 前后台切换
///   - 前台 → 后台：不停止同步（前台 Service 保活）
///   - 后台 → 前台：刷新 UI 状态
///   - dispose()：用户退出时才停止所有服务
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  // ── 服务实例 ──
  final _clipboard = ClipboardService();
  final _ws = WebSocketClient();
  final _discovery = UdpDiscovery();
  final _fg = ForegroundServiceBridge();
  final _nativeClip = NativeClipboardMonitor(); // 通道2：轮询补位微信
  StreamSubscription<A11yEvent>? _clipSub;      // 通道1：Listener 事件
  String? _pendingText;                        // WS断开期间待发送的剪贴板内容

  // ── UI 状态 ──
  final _roomCtrl = TextEditingController();
  bool _inRoom = false;
  String _roomCode = '';
  WsState _wsState = WsState.idle;
  final List<_LogItem> _log = [];

  // 用于取消 UDP 搜索 Stream
  StreamSubscription? _discoverySub;

  // ── 生命周期 ──

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindCallbacks();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    // 延迟一帧确保 context 可用
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    final perms = await PermissionService.checkAll();
    if (!mounted) return;
    if (!perms.allGranted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SetupWizardScreen()),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _leaveRoom();
    _roomCtrl.dispose();
    super.dispose();
  }

  /// App 前后台切换
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台 → 刷新 UI
    if (state == AppLifecycleState.resumed) {
      setState(() {});
    }
    // 注意：切后台时不停止同步！
    // 前台 Service 保持 WebSocket 连接和剪贴板轮询
  }

  // ── 回调绑定 ──

  /// 发送剪贴板到电脑，如果 WS 断开就暂存到 _pendingText
  void _sendOrStash(String text) {
    if (_ws.isConnected) {
      _ws.sendClipboard(text);
    } else {
      _pendingText = text;
      _addLog(LogKind.system, 'WS断开，暂存待发送');
    }
  }

  void _bindCallbacks() {
    _clipboard.onLocalCopy = (text) {
      _sendOrStash(text);
      _addLog(LogKind.phoneToPc, text);
    };

    _ws.onClipboardFromPc = (text) {
      _clipboard.setFromRemote(text);
      _nativeClip.markSelfChange(text);
      _addLog(LogKind.pcToPhone, text);
    };

    // WS 状态变化 → 刷新 UI + 补发暂存文本
    _ws.onStateChange = (state) {
      setState(() => _wsState = state);
      if (state == WsState.connected && _pendingText != null) {
        final text = _pendingText!;
        _pendingText = null;
        _ws.sendClipboard(text);
        _addLog(LogKind.phoneToPc, text);
        _addLog(LogKind.system, '连接恢复，补发暂存内容');
      }
    };

    _ws.onLog = (msg) => _addLog(LogKind.system, msg);
    _clipboard.onLog = (msg) => _addLog(LogKind.system, msg);

    _nativeClip.onChanged = (text) {
      _sendOrStash(text);
      _addLog(LogKind.phoneToPc, text);
    };
    _nativeClip.onLog = (msg) => _addLog(LogKind.system, msg);
  }

  // ── 加入 / 离开房间 ──

  Future<void> _joinRoom() async {
    final code = _roomCtrl.text.trim();
    if (code.length < 2) {
      _showTip('请输入至少 2 位数字房间号');
      return;
    }

    setState(() {
      _inRoom = true;
      _roomCode = code;
      _log.clear();
    });

    // 1. 启动前台保活服务（通知 + WAKE_LOCK）
    await _fg.start();

    // 2. 引导用户关闭电池优化（仅首次）
    _checkBatteryOpt();

    // 3. 启动双通道剪贴板采集
    _clipboard.start();
    _nativeClip.start();
    _startClipboardListener();
    // 4. 同步按钮由 ClipboardListener 自动触发，无需手动启动

    // 4. UDP 搜索 + WebSocket 连接
    _addLog(LogKind.system, '正在搜索房间 $_roomCode ...');
    _startDiscoveryLoop(code);
  }

  void _startDiscoveryLoop(String roomCode) async {
    // 取消上一次的搜索（如果有）
    _discoverySub?.cancel();
    _discovery.stop();

    try {
      await for (final info in _discovery.search(roomCode)) {
        if (!_inRoom) break; // 用户已离开房间

        _addLog(LogKind.system,
            '发现电脑 ${info['ip']}:${info['port']}');
        await _ws.connect(info);
      }
    } catch (_) {
      // Stream 被取消（正常情况）
    }
  }

  Future<void> _leaveRoom() async {
    setState(() => _inRoom = false);

    _discovery.stop();
    _discoverySub?.cancel();
    _ws.disconnect();
    _clipboard.stop();
    _nativeClip.stop();
    _stopClipboardListener();
    await _fg.stop();

    setState(() => _wsState = WsState.idle);
  }

  static const _channel = MethodChannel('ccv/sync_service');

  Future<void> _startClipboardListener() async {
    // 启动原生 ClipboardListenerService
    try { await _channel.invokeMethod('startClipboardListener'); } catch (_) {}
    // 订阅 EventChannel，接收 CLIP_CHANGE 事件
    final bridge = AccessibilityEventBridge();
    _clipSub = bridge.listen().listen((ev) {
      if (ev.sourceText.isNotEmpty) {
        if (ev.eventType == 'CLIP_CHANGE') {
          _sendOrStash(ev.sourceText);
          _addLog(LogKind.phoneToPc, ev.sourceText);
        } else if (ev.eventType == 'SYNC_BTN' || ev.eventType == 'AUTO_SYNC' || ev.eventType == 'BALL_CLICK') {
          _sendOrStash(ev.sourceText);
          _addLog(LogKind.phoneToPc, ev.sourceText);
          _addLog(LogKind.system, ev.eventType == 'AUTO_SYNC' ? '自动恢复 → 已同步' : '同步按钮 → 已发送');
        }
      }
    });
  }

  void _stopClipboardListener() {
    _clipSub?.cancel();
    _clipSub = null;
    try { _channel.invokeMethod('stopClipboardListener'); } catch (_) {}
  }

  // ── 电池优化引导 ──

  Future<void> _checkBatteryOpt() async {
    final disabled = await _fg.isBatteryOptimizationDisabled();
    if (disabled) return; // 已关闭，无需处理

    if (!mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提升后台稳定性'),
        content: const Text(
          '建议关闭 Ccv 的电池优化，这样切后台后同步不会中断。\n\n'
          '点击「去设置」→ 在列表中找到 Ccv → 选择"不优化"。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('稍后再说'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('去设置'),
          ),
        ],
      ),
    );

    if (go == true) {
      await _fg.openBatteryOptimizationSettings();
    }
  }

  // ── 日志 ──

  void _addLog(LogKind kind, String text) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, _LogItem(kind: kind, text: text));
      if (_log.length > 50) _log.removeLast();
    });
  }

  void _showTip(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  // ── UI 构建 ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ccv'),
        centerTitle: true,
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.bug_report, size: 20),
            tooltip: 'Debug',
            onSelected: (v) {
              if (v == 'a11y') {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const AccessibilityDebugScreen()));
              } else {
                Navigator.push(context, MaterialPageRoute(
                    builder: (_) => const ClipboardDebugScreen()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'a11y', child: Text('Accessibility')),
              PopupMenuItem(value: 'clip', child: Text('Clipboard')),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _statusDot(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // ── Logo + 标题 ──
            const Text('📋', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 4),
            Text(
              _inRoom ? '房间号: $_roomCode' : '电脑 ⇄ 手机 · 局域网直连',
              style: TextStyle(
                color: _inRoom ? Colors.blue : Colors.grey,
                fontSize: 13,
                fontWeight: _inRoom ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            const SizedBox(height: 20),

            // ── 房间号输入 + 按钮 ──
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _roomCtrl,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    keyboardType: TextInputType.number,
                    enabled: !_inRoom,
                    style:
                        const TextStyle(fontSize: 24, letterSpacing: 6),
                    decoration: const InputDecoration(
                      labelText: '房间号',
                      hintText: '如 1234',
                      border: OutlineInputBorder(),
                      counterText: '',
                    ),
                    onSubmitted: (_) => _inRoom ? null : _joinRoom(),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 56,
                  child: FilledButton.icon(
                    onPressed: _inRoom ? _leaveRoom : _joinRoom,
                    icon:
                        Icon(_inRoom ? Icons.link_off : Icons.link),
                    label: Text(_inRoom ? '离开' : '加入房间'),
                  ),
                ),
              ],
            ),

            // ── 连接状态 ──
            const SizedBox(height: 8),
            Text(_statusText(),
                style: TextStyle(
                    color: _wsState == WsState.connected
                        ? Colors.green
                        : Colors.grey,
                    fontSize: 13)),

            const Divider(height: 24),

            // ── 日志列表 ──
            Expanded(
              child: _log.isEmpty
                  ? const Center(
                      child: Text('复制文本即可同步\n电脑 ⇄ 手机',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey)),
                    )
                  : ListView.builder(
                      itemCount: _log.length,
                      itemBuilder: (_, i) {
                        final item = _log[i];
                        return Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            item.display,
                            style: const TextStyle(
                                fontSize: 12,
                                fontFamily: 'monospace'),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 状态指示灯
  Widget _statusDot() {
    final color = switch (_wsState) {
      WsState.connected => Colors.green,
      WsState.idle => Colors.grey,
      _ => Colors.orange,
    };
    return Icon(Icons.circle, size: 12, color: color);
  }

  /// 状态文字描述
  String _statusText() {
    if (!_inRoom) return '输入相同房间号即可连接';
    return switch (_wsState) {
      WsState.idle => '等待开始',
      WsState.discovering => '🔍 搜索房间中...',
      WsState.connecting => '🔗 连接中...',
      WsState.connected => '🟢 已连接 · 同步中',
      WsState.reconnecting => '🔄 重连中...',
    };
  }
}

// ── 日志数据模型 ──

enum LogKind { phoneToPc, pcToPhone, system }

class _LogItem {
  final LogKind kind;
  final String text;
  final DateTime time = DateTime.now();

  _LogItem({required this.kind, required this.text});

  String get display {
    final t =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final icon = switch (kind) {
      LogKind.phoneToPc => '📱→💻',
      LogKind.pcToPhone => '💻→📱',
      LogKind.system => ' ⚙ ',
    };
    final short = text.length > 28 ? '${text.substring(0, 28)}…' : text;
    return '$t $icon $short';
  }
}
