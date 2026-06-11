/// Ccv 全局常量
///
/// 所有端口和间隔集中管理，方便统一修改。
/// 注意：这些值必须与 Windows 端 server.cjs 中的值保持一致。
class Ccv {
  Ccv._(); // 防止实例化

  // ── 网络端口 ──
  /// WebSocket 服务端口（与 Windows 端 ws 端口一致）
  static const int wsPort = 9527;

  /// UDP 广播端口（与 Windows 端 UDP 广播目标端口一致）
  static const int udpPort = 9528;

  // ── 时间间隔 ──
  /// 剪贴板轮询间隔（毫秒）
  static const int clipboardPollMs = 500;

  /// WebSocket 心跳间隔（秒）
  static const int heartbeatSec = 10;

  /// UDP 发现单次超时（秒）
  static const int udpTimeoutSec = 8;

  /// UDP 发现失败后重试等待（秒）
  static const int udpRetryWaitSec = 2;

  // ── 重连参数 ──
  /// 重连初始延迟（秒）
  static const int reconnectBaseSec = 1;

  /// 重连最大延迟（秒）
  static const int reconnectMaxSec = 30;

  /// 重连退避倍数（每次失败后延迟 ×2）
  static const double reconnectMultiplier = 2.0;

  // ── Android 通知 ──
  /// 前台服务通知渠道 ID
  static const String notifChannelId = 'ccv_sync';

  /// 前台服务通知 ID
  static const int notifId = 1001;

  // ── MethodChannel ──
  /// 与原生 Android 通信的 MethodChannel 名称
  static const String methodChannel = 'ccv/sync_service';
}
