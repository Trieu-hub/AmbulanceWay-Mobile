import 'package:flutter/material.dart';

import 'app.dart';
import 'core/device_info.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Máy ảo hay điện thoại thật: để cảnh báo khi địa chỉ máy chủ là localhost / 10.0.2.2.
  await DeviceInfo.detect();
  // Thông báo hệ thống (ca SOS mới, trạng thái ca) khi app chạy nền.
  final notifier = await LocalNotifier.create();
  runApp(AmbulanceWayApp(notifier: notifier));
}
