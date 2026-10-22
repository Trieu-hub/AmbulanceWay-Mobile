import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

/// Cấu hình chung của app.
class AppConfig {
  AppConfig._();

  /// Có thể đặt sẵn địa chỉ máy chủ lúc build:
  /// `flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5199`
  static const String _envBaseUrl = String.fromEnvironment('API_BASE_URL');

  /// Cổng mặc định của backend ASP.NET (xem Properties/launchSettings.json).
  static const int backendPort = 5199;

  /// Địa chỉ máy chủ mặc định khi người dùng chưa nhập trong phần Cài đặt.
  static String get defaultBaseUrl {
    if (_envBaseUrl.isNotEmpty) return _envBaseUrl;
    // Máy ảo Android truy cập máy tính đang chạy backend qua 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:$backendPort';
    }
    return 'http://localhost:$backendPort';
  }

  static const String hubPath = '/ambulanceHub';

  /// Dùng cho header User-Agent khi tải ô bản đồ OpenStreetMap.
  static const String userAgentPackage = 'com.ambulanceway.ambulance_way';

  /// Tâm bản đồ mặc định (TP.HCM) - trùng DefaultMapLat/Lng trong appsettings.json.
  static const LatLng defaultCenter = LatLng(10.762622, 106.660172);

  /// Số điện thoại cấp cứu quốc gia.
  static const String emergencyNumber = '115';

  /// Tài xế có bấy nhiêu giây để nhận ca khi SOS vừa đến (giống bản web).
  static const int incomingSosSeconds = 15;

  /// Chu kỳ gửi vị trí GPS của tài xế lên máy chủ (giống bản web).
  static const Duration locationPushInterval = Duration(seconds: 5);
}
