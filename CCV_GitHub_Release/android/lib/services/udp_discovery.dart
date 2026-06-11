import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../constants.dart';

/// UDP 局域网房间发现
///
/// 工作原理：
///   Windows 端每 2 秒广播一次房间号，手机监听广播并匹配。
///
///   电脑 --[UDP 255.255.255.255:9528]--> 局域网所有设备
///   内容：{"type":"clipboard_room","room":"1234","ip":"192.168.0.100","port":9527}
///
/// 使用方式：
///   ```dart
///   final discovery = UdpDiscovery();
///   // 持续搜索直到找到（返回 Stream）
///   await for (final info in discovery.search('1234')) {
///     print('发现电脑: ${info['ip']}:${info['port']}');
///     break; // 找到后停止
///   }
///   ```
class UdpDiscovery {
  bool _active = false;

  /// 是否正在搜索
  bool get isActive => _active;

  /// 持续搜索指定房间号，每找到一个匹配就 yield 一次
  ///
  /// [roomCode] 用户输入的房间号
  ///
  /// yield 格式：{'ip': '192.168.x.x', 'port': 9527}
  Stream<Map<String, dynamic>> search(String roomCode) async* {
    _active = true;

    while (_active) {
      final result = await _singleScan(roomCode);

      if (result != null) {
        yield result;
        // 找到后停止（由上层调用 stop() 或退出 await for）
        break;
      }

      // 未找到，等待后重试
      if (_active) {
        await Future.delayed(Duration(seconds: Ccv.udpRetryWaitSec));
      }
    }

    _active = false;
  }

  /// 单次 UDP 扫描（监听广播直到超时或匹配成功）
  Future<Map<String, dynamic>?> _singleScan(String roomCode) async {
    final completer = Completer<Map<String, dynamic>?>();
    RawDatagramSocket? socket;
    Timer? timer;

    // ── 超时定时器 ──
    timer = Timer(Duration(seconds: Ccv.udpTimeoutSec), () {
      if (!completer.isCompleted) completer.complete(null);
    });

    // ── 绑定 UDP Socket，监听广播 ──
    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        Ccv.udpPort,
      );
    } catch (_) {
      // 端口被占用 → 随机端口（降低成功率但至少不崩溃）
      try {
        socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      } catch (_) {
        if (!completer.isCompleted) completer.complete(null);
        timer.cancel();
        return completer.future;
      }
    }

    // ── 处理收到的 UDP 数据包 ──
    socket.listen((RawSocketEvent event) {
      if (event != RawSocketEvent.read) return;

      final datagram = socket?.receive();
      if (datagram == null) return;

      try {
        final json = jsonDecode(utf8.decode(datagram.data)) as Map<String, dynamic>;

        // 匹配条件：type == 'clipboard_room' 且 room 匹配
        if (json['type'] == 'clipboard_room' &&
            json['room']?.toString() == roomCode) {
          final ip = json['ip']?.toString() ?? '';
          final port = int.tryParse(json['port']?.toString() ?? '0') ?? 0;

          if (ip.isNotEmpty && port > 0 && !completer.isCompleted) {
            timer?.cancel();
            completer.complete({'ip': ip, 'port': port});
          }
        }
      } catch (_) {
        // 非 JSON 数据或解析失败 → 忽略
      }
    });

    // ── 等待结果 ──
    final result = await completer.future;

    // ── 清理资源 ──
    timer.cancel();
    try { socket.close(); } catch (_) {}

    return result;
  }

  /// 停止搜索
  void stop() {
    _active = false;
  }
}
