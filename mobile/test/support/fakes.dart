import 'dart:async';
import 'dart:convert';

import 'package:ambulance_way/core/api_client.dart';
import 'package:ambulance_way/services/hub_client.dart';
import 'package:ambulance_way/services/location_service.dart';
import 'package:ambulance_way/services/notification_service.dart';
import 'package:ambulance_way/services/routing_service.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

http.Response jsonResponse(Object? body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

/// Backend giả: mỗi route là "METHOD /đường/dẫn" trả về JSON hoặc một http.Response.
class FakeBackend {
  final Map<String, Object? Function(http.Request request)> routes = {};

  /// Các request đã nhận, theo thứ tự.
  final List<http.Request> requests = [];

  List<String> get log =>
      requests.map((request) => '${request.method} ${request.url.path}').toList();

  /// Body JSON của request cuối cùng khớp [route].
  Map<String, dynamic> lastBody(String route) {
    final request = requests.lastWhere((r) => '${r.method} ${r.url.path}' == route);
    return jsonDecode(request.body) as Map<String, dynamic>;
  }

  late final ApiClient api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((request) async {
          requests.add(request);
          final handler = routes['${request.method} ${request.url.path}'];
          if (handler == null) {
            return jsonResponse({'message': 'Chưa khai báo route ${request.method} ${request.url.path}'}, 404);
          }
          final result = handler(request);
          return result is http.Response ? result : jsonResponse(result);
        }),
      )..token = 'test-token';
}

/// Hub giả: ghi lại các lần invoke và cho test tự phát sự kiện của máy chủ.
class FakeHub extends HubClient {
  FakeHub() : super('http://server');

  final Map<String, void Function(Object? payload)> handlers = {};
  final List<(String method, List<Object> args)> invocations = [];
  bool started = false;
  bool stopped = false;

  @override
  void on(String event, void Function(Object? payload) handler) => handlers[event] = handler;

  @override
  Future<void> start() async {
    started = true;
    status.value = HubStatus.connected;
    await onConnected?.call();
  }

  @override
  Future<bool> invoke(String method, List<Object> args) async {
    invocations.add((method, args));
    return true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    status.value = HubStatus.disconnected;
  }

  /// Giả lập máy chủ gửi [event] xuống. Payload đi qua JSON như khi truyền thật.
  void emit(String event, Object? payload) {
    final handler = handlers[event];
    if (handler == null) throw StateError('App chưa đăng ký sự kiện $event');
    handler(jsonDecode(jsonEncode(payload)));
  }

  List<List<Object>> calls(String method) => [
        for (final (name, args) in invocations)
          if (name == method) args,
      ];
}

/// Thiết bị không có GPS (máy tính, máy ảo chưa cấp quyền).
class NoGpsLocationService extends LocationService {
  @override
  Future<LocationIssue?> ensureReady() async => LocationIssue.unavailable;

  @override
  Future<LatLng?> current({Duration timeout = const Duration(seconds: 10)}) async => null;

  @override
  Stream<LatLng> watch({bool keepAliveInBackground = false}) => const Stream.empty();
}

/// GPS do test điều khiển: thêm vị trí hoặc lỗi vào [positions].
class ScriptedLocationService extends LocationService {
  final StreamController<LatLng> positions = StreamController<LatLng>.broadcast();

  @override
  Future<LocationIssue?> ensureReady() async => null;

  @override
  Future<LatLng?> current({Duration timeout = const Duration(seconds: 10)}) async => null;

  @override
  Stream<LatLng> watch({bool keepAliveInBackground = false}) => positions.stream;
}

/// Dịch vụ dẫn đường không có mạng: luôn rơi về ước lượng đường thẳng (kết quả tính được trong test).
RoutingService offlineRouting() => RoutingService(
      httpClient: MockClient((_) async => throw http.ClientException('offline')),
    );

/// Thông báo hệ thống giả: ghi lại các lần hiện thông báo.
class FakeNotifier implements AppNotifier {
  final List<(String kind, int id, String title, String body)> shown = [];
  int permissionRequests = 0;

  @override
  Future<void> requestPermission() async => permissionRequests++;

  @override
  Future<void> urgent(int id, String title, String body) async => shown.add(('urgent', id, title, body));

  @override
  Future<void> info(int id, String title, String body) async => shown.add(('info', id, title, body));
}
