import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../constants.dart';

/// WebSocket 连接状态
///
/// 用于 UI 显示不同的连接状态图标和文字
enum WsState {
  idle,          // 未开始
  discovering,   // 正在 UDP 搜索房间
  connecting,    // 正在 TCP 握手
  connected,     // 已连接，正常同步中
  reconnecting,  // 断线后正在等待重连
}

/// WebSocket 客户端（带心跳 + 自动重连）
///
/// 功能：
///   - 与 Windows 端 WebSocket 服务端建立长连接
///   - 每 10 秒发送 {"type":"ping"} 心跳包
///   - 断线后自动重连，延迟指数增长（1s→2s→4s→...→最大 30s）
///   - 收到电脑剪贴板 → 通过 [onClipboardFromPc] 回调通知
///   - 通过 [onStateChange] 回调通知 UI 更新连接状态
///
/// 使用方式：
///   ```dart
///   final ws = WebSocketClient();
///   ws.onClipboardFromPc = (text) => print('电脑复制了: $text');
///   ws.onStateChange = (state) => print('状态: $state');
///   await ws.connect('192.168.0.100', 9527);
///   ws.sendClipboard('手机复制的内容');
///   ```
class WebSocketClient {
  // ── 内部状态 ──
  WebSocketChannel? _channel;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _wantsConnection = false; // 用户是否期望保持连接

  String? _lastIp;
  int _lastPort = Ccv.wsPort;

  WsState _state = WsState.idle;

  // ── 公开回调 ──

  /// 收到电脑剪贴板内容时触发
  void Function(String text)? onClipboardFromPc;

  /// 连接状态变化时触发
  void Function(WsState state)? onStateChange;

  /// 日志回调（用于 UI 显示状态文字）
  void Function(String msg)? onLog;

  // ── 公开属性 ──

  WsState get state => _state;
  bool get isConnected => _state == WsState.connected;

  // ── 公开方法 ──

  /// 连接到指定 IP 和端口
  ///
  /// [info] 来自 UdpDiscovery.search() 的结果 {'ip': ..., 'port': ...}
  Future<void> connect(Map<String, dynamic> info) async {
    _lastIp = info['ip'] as String;
    _lastPort = info['port'] as int;
    _wantsConnection = true;
    _reconnectAttempts = 0;
    await _doConnect();
  }

  /// 发送剪贴板内容到电脑
  void sendClipboard(String text) {
    if (!isConnected) {
      _log('WS_SEND SKIPPED — not connected (state=$_state)');
      return;
    }
    if (_channel == null) {
      _log('WS_SEND SKIPPED — channel is null');
      return;
    }
    try {
      _channel!.sink.add(jsonEncode({
        'type': 'clipboard',
        'content': text,
      }));
      _log('WS_SEND OK: "${text.length > 30 ? '${text.substring(0, 30)}...' : text}"');
    } catch (e) {
      _log('WS_SEND FAILED: $e');
    }
  }

  /// 主动断开（用户点击离开按钮）
  void disconnect() {
    _wantsConnection = false;
    _stopHeartbeat();
    _stopReconnect();
    _channel?.sink.close();
    _channel = null;
    _setState(WsState.idle);
  }

  /// 释放所有资源
  void dispose() {
    disconnect();
  }

  // ── 内部实现 ──

  /// 执行 WebSocket 连接
  Future<void> _doConnect() async {
    if (!_wantsConnection) return;

    _setState(WsState.connecting);

    try {
      final url = 'ws://$_lastIp:$_lastPort';
      _log('连接 $url ...');

      _channel = WebSocketChannel.connect(Uri.parse(url));

      // 等待连接建立（超时 5 秒）
      await _channel!.ready.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException('连接超时'),
      );

      // ── 连接成功 → 停止重连 ──
      _setState(WsState.connected);
      _stopReconnect();
      _reconnectAttempts = 0;
      _startHeartbeat();
      _log('[WS] Connected');

      // 持续监听消息
      _channel!.stream.listen(
        _onServerMessage,
        onDone: _onDisconnected,
        onError: (_) => _onDisconnected(),
        cancelOnError: false,
      );
    } catch (e) {
      _log('连接失败: $e');
      _channel = null;
      _scheduleReconnect();
    }
  }

  /// 收到服务器消息
  void _onServerMessage(dynamic raw) {
    try {
      final msg = jsonDecode(raw as String) as Map<String, dynamic>;

      if (msg['type'] == 'clipboard' && msg['content'] != null) {
        // 电脑剪贴板 → 通知上层写入本地
        onClipboardFromPc?.call(msg['content'].toString());
      }
      // 其他消息类型（如之前版本的 sync-log 等）忽略
    } catch (_) {
      // 非 JSON（可能是心跳响应等），忽略
    }
  }

  /// 连接断开
  void _onDisconnected() {
    _channel = null;
    _stopHeartbeat();

    if (!_wantsConnection) {
      _setState(WsState.idle);
      return;
    }

    _log('[WS] Disconnected');
    _scheduleReconnect();
  }

  // ── 心跳机制 ──

  /// 启动心跳定时器：每 Ccv.heartbeatSec 秒发送一次 ping
  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: Ccv.heartbeatSec),
      (_) => _sendPing(),
    );
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// 发送心跳
  ///
  /// 发送 {"type":"ping"} 到电脑端。
  /// 注意：当前 Windows 端不检查 ping，但未来版本可以添加超时断线检测。
  void _sendPing() {
    if (!isConnected || _channel == null) return;
    try {
      _channel!.sink.add(jsonEncode({'type': 'ping'}));
    } catch (_) {
      _onDisconnected();
    }
  }

  // ── 重连机制 ──

  /// 重连退避序列：1s → 2s → 5s → 10s → 10s → ...
  static const _reconnectDelays = [1, 2, 5, 10];

  /// 安排重连（同一时间最多一个重连任务，_stopReconnect 保证）
  void _scheduleReconnect() {
    _setState(WsState.reconnecting);
    _stopReconnect(); // 取消旧任务，保证只有一个

    final idx = _reconnectAttempts < _reconnectDelays.length
        ? _reconnectAttempts
        : _reconnectDelays.length - 1;
    final sec = _reconnectDelays[idx];
    _reconnectAttempts++;

    _log('[WS] Reconnect in ${sec}s');
    _reconnectTimer = Timer(Duration(seconds: sec), () {
      if (_wantsConnection) _doConnect();
    });
  }

  void _stopReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  // ── 工具 ──

  void _setState(WsState s) {
    _state = s;
    // 用 microtask 避免在 build 期间 setState
    Future.microtask(() => onStateChange?.call(s));
  }

  void _log(String msg) {
    Future.microtask(() => onLog?.call(msg));
  }
}
