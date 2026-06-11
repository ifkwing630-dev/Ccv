import 'package:flutter/services.dart';

/// 三项权限的状态
class Permissions {
  final bool accessibility;
  final bool overlay;
  final bool batteryOptimization;

  Permissions({
    required this.accessibility,
    required this.overlay,
    required this.batteryOptimization,
  });

  bool get allGranted => accessibility && overlay && batteryOptimization;
}

/// 权限检测 & 跳转服务
///
/// 通过 MethodChannel "ccv/sync_service" 调用原生 Kotlin 代码：
///   checkAccessibility → 检查无障碍是否开启
///   checkOverlay       → 检查悬浮窗权限
///   isIgnoringBatteryOpt → 检查电池优化
///
/// 跳转系统设置：
///   openAccessibilitySettings
///   openOverlaySettings
///   requestBatteryOpt
class PermissionService {
  static const _channel = MethodChannel('ccv/sync_service');

  /// 检测全部三项权限
  static Future<Permissions> checkAll() async {
    final results = await Future.wait([
      _check('checkAccessibility'),
      _check('checkOverlay'),
      _check('isIgnoringBatteryOpt'),
    ]);
    return Permissions(
      accessibility: results[0],
      overlay: results[1],
      batteryOptimization: results[2],
    );
  }

  static Future<bool> _check(String method) async {
    try {
      final result = await _channel.invokeMethod<bool>(method);
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统无障碍设置
  static Future<void> openAccessibilitySettings() async {
    try {
      await _channel.invokeMethod('openAccessibilitySettings');
    } catch (_) {}
  }

  /// 跳转悬浮窗权限页
  static Future<void> openOverlaySettings() async {
    try {
      await _channel.invokeMethod('openOverlaySettings');
    } catch (_) {}
  }

  /// 跳转电池优化设置
  static Future<void> openBatteryOptimizationSettings() async {
    try {
      await _channel.invokeMethod('requestBatteryOpt');
    } catch (_) {}
  }
}
