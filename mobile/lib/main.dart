import 'package:flutter/material.dart';

import 'app.dart';
import 'core/device_info.dart';
import 'services/notification_service.dart';
import 'services/server_discovery.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Máy ảo hay điện thoại thật: để cảnh báo khi địa chỉ máy chủ là localhost / 10.0.2.2.
  await DeviceInfo.detect();
  // Thông báo hệ thống (ca SOS mới, trạng thái ca) khi app chạy nền.
  final notifier = await LocalNotifier.create();
  runApp(AmbulanceWayApp(
    notifier: notifier,
    // Điện thoại/máy ảo: IP máy tính chạy backend đổi theo Wi-Fi nên tự tìm lại khi mất kết nối.
    discovery: DeviceInfo.current.isMobile ? const ServerDiscovery() : null,
  ));
}
