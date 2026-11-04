import 'package:ambulance_way/app.dart';
import 'package:ambulance_way/core/api_client.dart';
import 'package:ambulance_way/core/device_info.dart';
import 'package:ambulance_way/services/server_discovery.dart';
import 'package:ambulance_way/state/app_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

/// Mạng giả: [found] là địa chỉ máy chủ "tìm thấy" trong Wi-Fi.
class FakeDiscovery implements ServerDiscovery {
  FakeDiscovery(this.found);

  String? found;
  int calls = 0;

  @override
  Future<String?> find({String? current}) async {
    calls++;
    return found;
  }
}

/// Chỉ máy chủ ở [aliveHost] trả lời; địa chỉ khác coi như mất kết nối (IP cũ của máy tính).
MockClient networkWithServerAt(String aliveHost, List<String> log) => MockClient((request) async {
      log.add('${request.url.host} ${request.url.path}');
      if (request.url.host != aliveHost) throw http.ClientException('timeout', request.url);
      return jsonResponse({'success': true, 'otp': '123456', 'expiresInSeconds': 300});
    });

void main() {
  group('ApiClient tự chuyển sang máy chủ mới', () {
    test('IP máy tính đổi: tìm lại máy chủ rồi gửi lại yêu cầu xin OTP tới địa chỉ mới', () async {
      final log = <String>[];
      final api = ApiClient(
        baseUrl: 'http://10.12.8.59:5199',
        httpClient: networkWithServerAt('172.20.10.2', log),
      );
      api.onUnreachable = () async => api.baseUrl = 'http://172.20.10.2:5199';

      final data = await api.post('/api/patientauth/register', body: {'PhoneNumber': '0943751258'});

      expect(data['otp'], '123456');
      expect(log, ['10.12.8.59 /api/patientauth/register', '172.20.10.2 /api/patientauth/register']);
    });

    test('máy chủ vẫn ở địa chỉ cũ (chỉ chậm) thì không gửi lại, tránh tạo trùng', () async {
      final log = <String>[];
      final api = ApiClient(
        baseUrl: 'http://10.12.8.59:5199',
        httpClient: networkWithServerAt('nowhere', log),
      );
      var searched = 0;
      api.onUnreachable = () async => searched++;

      await expectLater(api.post('/api/sos', body: {}), throwsA(isA<ApiException>()));
      expect(searched, 1);
      expect(log, hasLength(1));
    });

    test('chỉ gửi lại đúng một lần dù địa chỉ mới cũng không trả lời', () async {
      final log = <String>[];
      final api = ApiClient(
        baseUrl: 'http://10.0.0.1:5199',
        httpClient: networkWithServerAt('nowhere', log),
      );
      var next = 2;
      api.onUnreachable = () async => api.baseUrl = 'http://10.0.0.${next++}:5199';

      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('10.0.0.2'))),
      );
      expect(log, ['10.0.0.1 /x', '10.0.0.2 /x']);
    });
  });

  group('AppState.rediscoverServer', () {
    setUp(() => SharedPreferences.setMockInitialValues({'server_url': 'http://10.12.8.59:5199'}));

    test('mở app sau khi đổi Wi-Fi: tự sửa và lưu địa chỉ mới', () async {
      final discovery = FakeDiscovery('http://172.20.10.2:5199');
      final app = AppState(discovery: discovery);
      await app.load();
      // load() kiểm tra máy chủ ở nền.
      await pumpEventQueue();

      expect(app.baseUrl, 'http://172.20.10.2:5199');
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server_url'), 'http://172.20.10.2:5199');
      expect(discovery.calls, 1);
    });

    test('không thấy máy chủ thì giữ địa chỉ cũ và không quét lại liên tục', () async {
      final discovery = FakeDiscovery(null);
      final app = AppState(discovery: discovery);
      await app.load();
      await pumpEventQueue();

      expect(app.baseUrl, 'http://10.12.8.59:5199');
      expect(await app.rediscoverServer(), isNull);
      expect(discovery.calls, 1, reason: 'vừa quét thất bại, chưa quét lại');

      discovery.found = 'http://172.20.10.2:5199';
      expect(await app.rediscoverServer(force: true), 'http://172.20.10.2:5199');
      expect(app.baseUrl, 'http://172.20.10.2:5199');
    });

    test('nhiều yêu cầu lỗi cùng lúc chỉ quét mạng một lần', () async {
      final discovery = FakeDiscovery('http://172.20.10.2:5199');
      final app = AppState(discovery: discovery);
      await Future.wait([app.rediscoverServer(), app.rediscoverServer(), app.rediscoverServer()]);
      expect(discovery.calls, 1);
    });

    test('không truyền discovery (máy tính, web) thì không tự tìm', () async {
      final app = AppState();
      await app.load();
      expect(app.canDiscover, isFalse);
      expect(await app.rediscoverServer(force: true), isNull);
    });
  });

  group('Màn hình Cài đặt máy chủ', () {
    late DeviceInfo saved;
    setUp(() => saved = DeviceInfo.current);
    tearDown(() => DeviceInfo.current = saved);

    testWidgets('gõ địa chỉ mới rồi quay lại mà chưa lưu thì app hỏi, chọn Lưu là lưu', (tester) async {
      DeviceInfo.current = const DeviceInfo(platform: TargetPlatform.android, isEmulator: false);
      SharedPreferences.setMockInitialValues({'server_url': 'http://10.12.8.59:5199'});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cài đặt máy chủ'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'http://172.20.10.2:5199');
      await tester.pump();
      await tester.binding.handlePopRoute(); // nút Back của Android
      await tester.pumpAndSettle();
      expect(find.text('Chưa lưu địa chỉ mới'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Lưu')));
      await tester.pumpAndSettle();
      expect(find.text('Máy chủ: http://172.20.10.2:5199'), findsOneWidget);
    });

    testWidgets('chọn "Bỏ thay đổi" thì giữ địa chỉ cũ', (tester) async {
      DeviceInfo.current = const DeviceInfo(platform: TargetPlatform.android, isEmulator: false);
      SharedPreferences.setMockInitialValues({'server_url': 'http://10.12.8.59:5199'});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cài đặt máy chủ'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'http://172.20.10.2:5199');
      await tester.pump();
      await tester.binding.handlePopRoute(); // nút Back của Android
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ thay đổi'));
      await tester.pumpAndSettle();

      expect(find.text('Máy chủ: http://10.12.8.59:5199'), findsOneWidget);
    });

    testWidgets('nút "Tự tìm máy chủ" điền và lưu địa chỉ tìm thấy', (tester) async {
      DeviceInfo.current = const DeviceInfo(platform: TargetPlatform.android, isEmulator: false);
      SharedPreferences.setMockInitialValues({'server_url': 'http://10.12.8.59:5199'});
      final discovery = FakeDiscovery(null);

      await tester.pumpWidget(AmbulanceWayApp(discovery: discovery));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cài đặt máy chủ'));
      await tester.pumpAndSettle();

      discovery.found = 'http://172.20.10.2:5199';
      await tester.tap(find.text('Tự tìm máy chủ trong Wi-Fi'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Đã tìm thấy máy chủ tại http://172.20.10.2:5199'), findsOneWidget);
      await tester.binding.handlePopRoute(); // nút Back của Android
      await tester.pumpAndSettle();
      expect(find.text('Chưa lưu địa chỉ mới'), findsNothing);
      expect(find.text('Máy chủ: http://172.20.10.2:5199'), findsOneWidget);
    });
  });
}
