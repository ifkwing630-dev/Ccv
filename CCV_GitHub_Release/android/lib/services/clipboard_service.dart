import 'dart:async';
import 'package:flutter/services.dart';
import '../constants.dart';

/// 本地剪贴板监听服务
///
/// ## 工作原理
///
/// 每 500ms 调用 Flutter 的 Clipboard.getData() 检查系统剪贴板。
/// 当检测到新内容时，通过 [onLocalCopy] 回调通知上层发送到电脑。
///
/// ## 防循环机制
///
/// 场景：手机复制 "hello" → 发送给电脑 → 电脑写入剪贴板 →
///       电脑轮询检测到 → 发回手机 → 手机收到 →
///       写回手机剪贴板 → 如果不停，死循环！
///
/// 解决方案（_selfChange 标记）：
///   setFromRemote() 写入时打标记 → 下次轮询检测到标记 → 跳过 → 复位
///
/// ## ⚠️ Android 14 后台限制
///
/// Android 14+ 系统禁止后台应用读取剪贴板（即使有前台 Service）。
/// 这是 Android Framework 层的强制限制，无法绕过。
///
/// 具体影响：
///   - App 在前台 → Clipboard.getData() 正常返回内容 ✅
///   - App 在后台 → Clipboard.getData() 返回 null/空 ❌
///
/// 因此：
///   - 手机复制 → 电脑：仅在前台时生效
///   - 电脑复制 → 手机：不受影响（写入 Clip 无限制）
///
/// 本类内部用 _backgroundWarningIssued 标志，
/// 仅在第一次后台读取失败时记录一次警告，避免日志刷屏。
class ClipboardService {
  Timer? _timer;
  String _lastText = '';
  bool _selfChange = false;

  // ── 回调 ──

  /// 用户在本机复制了新内容 → 需要发送给电脑
  void Function(String text)? onLocalCopy;

  /// 调试/状态日志
  void Function(String msg)? onLog;

  // ── 公开方法 ──

  /// 启动轮询
  void start() {
    stop();
    _timer = Timer.periodic(
      Duration(milliseconds: Ccv.clipboardPollMs),
      (_) => _poll(),
    );
  }

  /// 停止轮询
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 收到电脑发来的内容 → 写入本地剪贴板
  ///
  /// 此方法会设置防循环标记，确保不会把电脑发来的内容再发回电脑。
  Future<void> setFromRemote(String text) async {
    if (text == _lastText) return; // 已经是最新，无需重复写

    _selfChange = true;
    _lastText = text;

    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (e) {
      _selfChange = false; // 写入失败，复位标记
      onLog?.call('写入剪贴板失败: $e');
    }
  }

  /// 是否在运行
  bool get isRunning => _timer != null;

  // ── 内部 ──

  Future<void> _poll() async {
    // 1. 尝试读取系统剪贴板
    String current;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      current = data?.text ?? '';
    } catch (_) {
      return; // 读取异常，跳过本轮
    }

    // 2. 空内容 → 跳过
    if (current.isEmpty) return;

    // 3. 防循环：刚刚由 setFromRemote 写入
    if (_selfChange) {
      _selfChange = false;
      return;
    }

    // 4. 去重：与上次相同
    if (current == _lastText) return;

    // ── 5. 检测到新内容！ ──
    _lastText = current;
    onLocalCopy?.call(current);
  }
}
