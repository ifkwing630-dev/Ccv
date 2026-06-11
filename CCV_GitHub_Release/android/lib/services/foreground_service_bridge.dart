import 'package:flutter/services.dart';
import '../constants.dart';

/// 原生 Android 前台服务桥接
///
/// 通过 MethodChannel 调用 Kotlin 层的 ClipboardSyncService：
///   - start() → 启动前台 Service + 显示通知 + 获取 WAKE_LOCK
///   - stop()  → 停止前台 Service + 取消通知 + 释放 WAKE_LOCK
///
/// 前台服务的作用（在 Android 系统眼中的地位）：
///   1. 通知栏显示 "Ccv 同步中"，用户知道 App 在后台工作
///   2. 进程优先级提升为 "前台进程"，系统不会轻易杀死
///   3. WAKE_LOCK 保持 CPU 不深度休眠
///
/// ⚠️ 注意：前台服务不能让 App 绕过 Android 14 的后台剪贴板读取限制。
/// 那是由 ClipboardManager 内部基于 Activity 可见性判断的。
class ForegroundServiceBridge {
  static const _channel = MethodChannel(Ccv.methodChannel);

  bool _running = false;
  bool get isRunning => _running;

  /// 启动前台服务
  Future<void> start() async {
    if (_running) return;
    try {
      await _channel.invokeMethod('startForegroundService');
      _running = true;
    } catch (_) {
      // 极少见：MethodChannel 未注册（Android 启动异常等）
    }
  }

  /// 停止前台服务
  Future<void> stop() async {
    if (!_running) return;
    try {
      await _channel.invokeMethod('stopForegroundService');
      _running = false;
    } catch (_) {}
  }

  /// 检查是否已加入电池优化白名单
  Future<bool> isBatteryOptimizationDisabled() async {
    try {
      final result = await _channel.invokeMethod('isIgnoringBatteryOpt');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统电池优化设置页
  Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('requestBatteryOpt');
    } catch (_) {}
  }
}
