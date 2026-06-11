import 'dart:async';
import 'package:flutter/services.dart';

/// 无障碍事件数据模型
class A11yEvent {
  final String time;
  final String eventType;
  final String packageName;
  final String className;
  final String eventText;
  final String sourceText;

  A11yEvent({
    required this.time,
    required this.eventType,
    required this.packageName,
    required this.className,
    required this.eventText,
    required this.sourceText,
  });

  factory A11yEvent.fromMap(Map<dynamic, dynamic> map) {
    return A11yEvent(
      time: map['time']?.toString() ?? '',
      eventType: map['eventType']?.toString() ?? '',
      packageName: map['packageName']?.toString() ?? '',
      className: map['className']?.toString() ?? '',
      eventText: map['eventText']?.toString() ?? '',
      sourceText: map['sourceText']?.toString() ?? '',
    );
  }
}

/// 无障碍事件桥接（通过 EventChannel 从 Kotlin 层接收事件）
///
/// 使用 EventChannel 而非 MethodChannel，因为 Native 端主动推送，
/// Dart 端被动接收，符合 Stream 模式。
class AccessibilityEventBridge {
  static const _channelName = 'ccv/a11y_events';

  Stream<A11yEvent> listen() {
    // receiveBroadcastStream 在 Flutter 引擎层注册 EventChannel 监听器，
    // 对应 Kotlin 端 EventChannel.StreamHandler.onListen
    return EventChannel(_channelName)
        .receiveBroadcastStream()
        .map((data) => A11yEvent.fromMap(data as Map<dynamic, dynamic>));
  }
}
