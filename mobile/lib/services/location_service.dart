import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Lý do không lấy được vị trí, kèm câu giải thích cho người dùng.
enum LocationIssue {
  serviceDisabled('Thiết bị đang tắt định vị (GPS).'),
  permissionDenied('Ứng dụng chưa được cấp quyền vị trí.'),
  permissionDeniedForever(
      'Quyền vị trí đã bị chặn. Hãy bật lại trong phần cài đặt của thiết bị.'),
  unavailable('Không lấy được vị trí hiện tại.');

  const LocationIssue(this.message);

  final String message;
}

/// Bọc plugin geolocator: xin quyền, lấy vị trí một lần và theo dõi liên tục.
class LocationService {
  static const LocationSettings _settings =
      LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);

  /// Trả về null nếu đã sẵn sàng định vị, ngược lại là lý do.
  Future<LocationIssue?> ensureReady() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return LocationIssue.serviceDisabled;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        // Trên trình duyệt, hộp thoại xin quyền có thể bị bỏ lơ nên phải giới hạn thời gian chờ.
        permission = await Geolocator.requestPermission()
            .timeout(const Duration(seconds: 20));
      }
      switch (permission) {
        case LocationPermission.denied:
        case LocationPermission.unableToDetermine:
          return LocationIssue.permissionDenied;
        case LocationPermission.deniedForever:
          return LocationIssue.permissionDeniedForever;
        case LocationPermission.whileInUse:
        case LocationPermission.always:
          return null;
      }
    } on Exception {
      return LocationIssue.unavailable;
    }
  }

  /// Vị trí hiện tại, hoặc null nếu không lấy được trong [timeout].
  Future<LatLng?> current({Duration timeout = const Duration(seconds: 10)}) async {
    if (await ensureReady() != null) return null;
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      ).timeout(timeout + const Duration(seconds: 2));
      return LatLng(position.latitude, position.longitude);
    } on Exception {
      try {
        final last = await Geolocator.getLastKnownPosition();
        return last == null ? null : LatLng(last.latitude, last.longitude);
      } on Exception {
        // Trình duyệt không hỗ trợ "vị trí gần nhất".
        return null;
      }
    }
  }

  /// Luồng vị trí liên tục. Gọi [ensureReady] trước khi lắng nghe.
  ///
  /// [keepAliveInBackground]: trên Android chạy GPS trong dịch vụ nền (foreground service) kèm thông báo
  /// thường trực, nhờ vậy khi tài xế tắt màn hình hay chuyển sang app khác, app vẫn gửi vị trí và
  /// vẫn nhận được ca SOS mới qua SignalR.
  Stream<LatLng> watch({bool keepAliveInBackground = false}) {
    final LocationSettings settings =
        keepAliveInBackground && !kIsWeb && defaultTargetPlatform == TargetPlatform.android
            ? AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 5,
                foregroundNotificationConfig: const ForegroundNotificationConfig(
                  notificationTitle: 'AmbulanceWay: đang trực',
                  notificationText: 'Đang chia sẻ vị trí xe để nhận ca cấp cứu gần bạn',
                  notificationChannelName: 'Ca trực',
                  enableWakeLock: true,
                  enableWifiLock: true,
                  setOngoing: true,
                ),
              )
            : _settings;
    return Geolocator.getPositionStream(locationSettings: settings)
        .map((position) => LatLng(position.latitude, position.longitude));
  }
}
