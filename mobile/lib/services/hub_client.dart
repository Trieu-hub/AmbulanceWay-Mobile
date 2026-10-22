import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:signalr_netcore/signalr_client.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';

enum HubStatus { disconnected, connecting, connected }

/// Kết nối SignalR tới AmbulanceHub của backend.
///
/// Tự kết nối lại khi rớt mạng và gọi [onConnected] sau mỗi lần nối được,
/// vì máy chủ quên các đăng ký (RegisterDriver, JoinCase) khi kết nối cũ mất.
class HubClient {
  HubClient(String baseUrl)
      : _url = '${ApiClient.normalizeBaseUrl(baseUrl)}${AppConfig.hubPath}';

  final String _url;
  final Map<String, void Function(Object? payload)> _handlers = {};

  HubConnection? _connection;
  Timer? _retryTimer;
  bool _wanted = false;
  bool _starting = false;

  /// Trạng thái kết nối để giao diện hiển thị.
  final ValueNotifier<HubStatus> status = ValueNotifier(HubStatus.disconnected);

  /// Gọi sau mỗi lần kết nối (hoặc kết nối lại) thành công.
  Future<void> Function()? onConnected;

  bool get isConnected => status.value == HubStatus.connected;

  /// Đăng ký hàm xử lý cho một sự kiện máy chủ gửi xuống.
  /// [handler] nhận tham số đầu tiên của sự kiện (object hoặc mảng JSON).
  void on(String event, void Function(Object? payload) handler) {
    _handlers[event] = handler;
  }

  /// Bắt đầu kết nối và giữ kết nối cho tới khi gọi [stop].
  Future<void> start() async {
    _wanted = true;
    await _connect();
  }

  Future<void> _connect() async {
    if (!_wanted || _starting || isConnected) return;
    _starting = true;
    _retryTimer?.cancel();
    status.value = HubStatus.connecting;

    final connection = HubConnectionBuilder()
        .withUrl(_url)
        .withAutomaticReconnect(retryDelays: [0, 2000, 5000, 10000, 15000])
        .build();

    _handlers.forEach((event, handler) {
      connection.on(event, (arguments) {
        handler(arguments == null || arguments.isEmpty ? null : arguments.first);
      });
    });

    connection.onreconnecting(({error}) {
      if (_connection == connection) status.value = HubStatus.connecting;
    });
    connection.onreconnected(({connectionId}) {
      if (_connection != connection) return;
      status.value = HubStatus.connected;
      _notifyConnected();
    });
    connection.onclose(({error}) {
      if (_connection != connection) return;
      status.value = HubStatus.disconnected;
      _scheduleRetry();
    });

    _connection = connection;
    try {
      await connection.start();
      if (!_wanted || _connection != connection) {
        await connection.stop();
        return;
      }
      status.value = HubStatus.connected;
      _notifyConnected();
    } catch (_) {
      // Thư viện ném nhiều kiểu lỗi khác nhau khi máy chủ chưa bật; cứ thử lại sau.
      if (_connection == connection) {
        status.value = HubStatus.disconnected;
        _scheduleRetry();
      }
    } finally {
      _starting = false;
    }
  }

  void _notifyConnected() {
    final callback = onConnected;
    if (callback == null) return;
    unawaited(callback().catchError((Object _) {}));
  }

  void _scheduleRetry() {
    if (!_wanted) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 5), _connect);
  }

  /// Gọi một hàm trên hub. Trả về false nếu đang mất kết nối hoặc máy chủ báo lỗi.
  Future<bool> invoke(String method, List<Object> args) async {
    final connection = _connection;
    if (connection == null || !isConnected) return false;
    try {
      await connection.invoke(method, args: args);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stop() async {
    _wanted = false;
    _retryTimer?.cancel();
    final connection = _connection;
    _connection = null;
    status.value = HubStatus.disconnected;
    try {
      await connection?.stop();
    } catch (_) {
      // Kết nối đã đóng sẵn.
    }
  }

  void dispose() {
    unawaited(stop());
    status.dispose();
  }
}
