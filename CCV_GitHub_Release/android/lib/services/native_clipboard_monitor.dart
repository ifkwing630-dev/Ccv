import 'dart:async';
import 'package:flutter/services.dart';

class NativeClipboardMonitor {
  static const _channel = MethodChannel('ccv/sync_service');

  Timer? _timer;
  String _lastText = '';
  bool _selfChange = false;
  int _pollCount = 0;

  void Function(String text)? onChanged;
  void Function(String msg)? onLog;

  bool get isRunning => _timer != null;

  void start() {
    stop();
    _pollCount = 0;
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _poll(),
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void markSelfChange(String text) {
    _selfChange = true;
    _lastText = text;
  }

  Future<void> _poll() async {
    _pollCount++;
    String text;
    try {
      final raw = await _channel.invokeMethod<String>('readClipboard') ?? '';
      if (raw.isEmpty || raw.startsWith('|')) return;
      final pipe = raw.indexOf('|');
      text = pipe > 0 ? raw.substring(0, pipe) : raw;
    } catch (_) {
      if (_pollCount <= 3) onLog?.call('POLL #$_pollCount ERROR');
      return;
    }

    if (text.isEmpty) return;
    if (_selfChange) { _selfChange = false; return; }
    if (text == _lastText) return;

    _lastText = text;
    onLog?.call('POLL #$_pollCount DETECTED: "${text.length > 30 ? '${text.substring(0, 30)}...' : text}"');
    onChanged?.call(text);
  }
}
