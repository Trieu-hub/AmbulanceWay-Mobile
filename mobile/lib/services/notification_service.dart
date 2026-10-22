import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thông báo hệ thống của điện thoại (thanh thông báo, có âm thanh và rung).
///
/// Chỉ hiện khi app không ở màn hình chính (đang chạy nền, màn hình tắt), vì lúc app đang mở
/// giao diện đã có hộp thoại và snackbar riêng.
abstract class AppNotifier {
  /// Hỏi quyền hiển thị thông báo (Android 13+, iOS). Gọi khi người dùng bắt đầu dùng chức năng cần nó.
  Future<void> requestPermission();

  /// Ca SOS mới cho tài xế: mức ưu tiên cao, rung mạnh.
  Future<void> urgent(int id, String title, String body);

  /// Cập nhật trạng thái ca cho người dân.
  Future<void> info(int id, String title, String body);
}

/// Dùng trong test và trên nền tảng không hỗ trợ (web, desktop).
class NoopNotifier implements AppNotifier {
  const NoopNotifier();

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> urgent(int id, String title, String body) async {}

  @override
  Future<void> info(int id, String title, String body) async {}
}

/// Thông báo cục bộ qua flutter_local_notifications (Android, iOS).
class LocalNotifier implements AppNotifier {
  LocalNotifier._();

  static const AndroidNotificationDetails _urgentAndroid = AndroidNotificationDetails(
    'sos_requests',
    'Ca cấp cứu mới',
    channelDescription: 'Báo cho tài xế đang trực khi có SOS gần đó',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    ticker: 'Ca cấp cứu mới',
  );

  static const AndroidNotificationDetails _infoAndroid = AndroidNotificationDetails(
    'case_updates',
    'Trạng thái ca cấp cứu',
    channelDescription: 'Tài xế nhận ca, xe đã đón, bệnh viện tiếp nhận...',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const DarwinNotificationDetails _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentSound: true,
  );

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Bản thật trên Android/iOS, bản rỗng ở nơi khác. Không bao giờ ném lỗi làm hỏng app.
  static Future<AppNotifier> create() async {
    final supported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS);
    if (!supported) return const NoopNotifier();
    final notifier = LocalNotifier._();
    try {
      await notifier._plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Hỏi quyền lúc cần (requestPermission), không hỏi ngay khi mở app.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestSoundPermission: false,
            requestBadgePermission: false,
          ),
        ),
      );
      notifier._ready = true;
    } on Exception catch (error) {
      debugPrint('Không khởi tạo được thông báo: $error');
    }
    return notifier;
  }

  @override
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    } on Exception catch (error) {
      debugPrint('Không xin được quyền thông báo: $error');
    }
  }

  bool get _appInForeground =>
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;

  Future<void> _show(int id, String title, String body, AndroidNotificationDetails android) async {
    if (!_ready || _appInForeground) return;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(android: android, iOS: _darwin),
      );
    } on Exception catch (error) {
      debugPrint('Không hiện được thông báo: $error');
    }
  }

  @override
  Future<void> urgent(int id, String title, String body) => _show(id, title, body, _urgentAndroid);

  @override
  Future<void> info(int id, String title, String body) => _show(id, title, body, _infoAndroid);
}
