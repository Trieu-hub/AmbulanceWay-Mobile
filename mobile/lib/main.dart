import 'package:flutter/material.dart';

import 'app.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Thông báo hệ thống (ca SOS mới, trạng thái ca) khi app chạy nền.
  final notifier = await LocalNotifier.create();
  runApp(AmbulanceWayApp(notifier: notifier));
}
