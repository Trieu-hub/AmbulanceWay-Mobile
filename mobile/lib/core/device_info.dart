import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'simulator_env_stub.dart' if (dart.library.io) 'simulator_env_io.dart';

/// Thiết bị đang chạy app.
///
/// Cần biết để kiểm tra địa chỉ máy chủ: "localhost" chỉ trỏ tới máy tính chạy backend khi app
/// chạy trên chính máy tính đó (hoặc iOS Simulator), còn "10.0.2.2" chỉ dùng được trong máy ảo
/// Android. Trên điện thoại thật cả hai đều không tới được backend.
class DeviceInfo {
  const DeviceInfo({
    required this.platform,
    this.isWeb = false,
    this.isEmulator,
    this.pageHost,
  });

  final TargetPlatform platform;
  final bool isWeb;

  /// Máy ảo Android hoặc iOS Simulator. null: chưa xác định được.
  final bool? isEmulator;

  /// Bản web: host của trang đang mở app (ví dụ "localhost" hoặc "192.168.1.10").
  final String? pageHost;

  bool get isAndroid => !isWeb && platform == TargetPlatform.android;

  bool get isIOS => !isWeb && platform == TargetPlatform.iOS;

  /// Android/iOS, kể cả máy ảo.
  bool get isMobile => isAndroid || isIOS;

  /// Thiết bị di động thật, hoặc chưa biết có phải máy ảo không.
  bool get maybePhysicalPhone => isMobile && isEmulator != true;

  /// Thiết bị hiện tại. Mặc định chưa biết có phải máy ảo không; main() gọi [detect] để hỏi nền tảng.
  static DeviceInfo current = DeviceInfo(
    platform: defaultTargetPlatform,
    isWeb: kIsWeb,
    pageHost: kIsWeb ? Uri.base.host : null,
  );

  static const MethodChannel _channel = MethodChannel('ambulance_way/device');

  /// Xác định máy ảo hay máy thật, gọi một lần trước runApp().
  static Future<void> detect() async {
    if (kIsWeb) return;
    bool? emulator;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        // MainActivity.kt trả lời kênh này.
        emulator = await _channel.invokeMethod<bool>('isEmulator');
      } on PlatformException {
        emulator = null;
      } on MissingPluginException {
        emulator = null;
      }
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      emulator = isIosSimulator();
    }
    current = DeviceInfo(platform: defaultTargetPlatform, isEmulator: emulator);
  }
}
