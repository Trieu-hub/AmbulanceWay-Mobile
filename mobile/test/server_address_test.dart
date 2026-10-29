import 'package:ambulance_way/app.dart';
import 'package:ambulance_way/core/api_client.dart';
import 'package:ambulance_way/core/device_info.dart';
import 'package:ambulance_way/core/server_address.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const phone = DeviceInfo(platform: TargetPlatform.android, isEmulator: false);
const emulator = DeviceInfo(platform: TargetPlatform.android, isEmulator: true);
const androidUnknown = DeviceInfo(platform: TargetPlatform.android);
const iphone = DeviceInfo(platform: TargetPlatform.iOS, isEmulator: false);
const iosSimulator = DeviceInfo(platform: TargetPlatform.iOS, isEmulator: true);
const windows = DeviceInfo(platform: TargetPlatform.windows);
const webOnLaptop = DeviceInfo(platform: TargetPlatform.windows, isWeb: true, pageHost: 'localhost');
const webOnPhone =
    DeviceInfo(platform: TargetPlatform.android, isWeb: true, pageHost: '192.168.1.10');

void main() {
  group('ServerAddress.problem', () {
    test('localhost trên điện thoại thật bị báo và chỉ cách nhập IP máy tính', () {
      for (final url in ['http://localhost:5199', 'localhost:5199', 'http://127.0.0.1:5199']) {
        final problem = ServerAddress.problem(url, phone);
        expect(problem, contains('chính điện thoại'), reason: url);
        expect(problem, contains('ipconfig'), reason: url);
      }
      expect(ServerAddress.problem('http://localhost:5199', iphone), contains('iPhone'));
      expect(ServerAddress.problem('http://localhost:5199', androidUnknown), contains('10.0.2.2'));
    });

    test('localhost dùng được trên máy tính, trình duyệt cùng máy và iOS Simulator', () {
      expect(ServerAddress.problem('http://localhost:5199', windows), isNull);
      expect(ServerAddress.problem('http://localhost:5199', webOnLaptop), isNull);
      expect(ServerAddress.problem('http://localhost:5199', iosSimulator), isNull);
    });

    test('máy ảo Android: localhost sai, 10.0.2.2 đúng', () {
      expect(ServerAddress.problem('http://localhost:5199', emulator), contains('10.0.2.2'));
      expect(ServerAddress.problem('http://10.0.2.2:5199', emulator), isNull);
    });

    test('10.0.2.2 chỉ dành cho máy ảo Android', () {
      expect(ServerAddress.problem('http://10.0.2.2:5199', phone), contains('máy ảo Android'));
      expect(ServerAddress.problem('http://10.0.2.2:5199', androidUnknown), contains('điện thoại thật'));
      expect(ServerAddress.problem('http://10.0.2.2:5199', windows), contains('localhost'));
      expect(ServerAddress.problem('http://10.0.2.2:5199', iphone), contains('máy ảo Android'));
    });

    test('trang web mở trên điện thoại mà máy chủ là localhost', () {
      expect(ServerAddress.problem('http://localhost:5199', webOnPhone), contains('192.168.1.10'));
    });

    test('0.0.0.0 (chép từ dòng "Now listening on") không dùng để kết nối', () {
      for (final device in [phone, emulator, windows]) {
        expect(ServerAddress.problem('http://0.0.0.0:5199', device), contains('0.0.0.0'));
      }
      expect(ServerAddress.problem('http://0.0.0.0:5199', emulator), contains('10.0.2.2'));
    });

    test('các lỗi gõ địa chỉ thường gặp', () {
      expect(ServerAddress.problem('https://192.168.1.10:5199', phone), contains('http://192.168.1.10:5199'));
      expect(ServerAddress.problem('192.168.1.10', phone), contains('Thiếu cổng'));
      expect(ServerAddress.problem('http://192.168.1.10:5199/api/mobile/ping', phone),
          contains('http://192.168.1.10:5199'));
      expect(ServerAddress.problem('192,168,1,10:5199', phone), contains('dấu chấm'));
      expect(ServerAddress.problem('ftp://192.168.1.10:5199', phone), contains('http://'));
      expect(ServerAddress.problem('   ', phone), isNotNull);
    });

    test('địa chỉ đúng thì không báo gì', () {
      expect(ServerAddress.problem('http://192.168.1.10:5199', phone), isNull);
      expect(ServerAddress.problem('192.168.1.10:5199/', phone), isNull);
      expect(ServerAddress.problem('https://ambulance.example.com', phone), isNull);
      expect(ServerAddress.problem('http://192.168.1.10:5199', windows), isNull);
    });
  });

  group('ApiClient khi không kết nối được', () {
    late DeviceInfo saved;
    setUp(() => saved = DeviceInfo.current);
    tearDown(() => DeviceInfo.current = saved);

    Future<ApiException> failWith(String baseUrl, Object error) async {
      final api = ApiClient(baseUrl: baseUrl, httpClient: MockClient((_) async => throw error));
      try {
        await api.post('/api/patientauth/login', body: {'PhoneNumber': '0987654321'});
      } on ApiException catch (e) {
        return e;
      }
      fail('phải ném ApiException');
    }

    test('điện thoại thật trỏ vào localhost: nói rõ lý do thay vì chỉ "kiểm tra mạng"', () async {
      DeviceInfo.current = phone;
      final error = await failWith('http://localhost:5199', http.ClientException('refused'));
      expect(error.isNetworkError, isTrue);
      expect(error.message, contains('http://localhost:5199'));
      expect(error.message, contains('chính điện thoại'));
    });

    test('địa chỉ hợp lệ nhưng không tới được: nhắc các bước kiểm tra', () async {
      DeviceInfo.current = phone;
      final error = await failWith('http://192.168.1.10:5199', http.ClientException('timeout'));
      expect(error.message, contains('--launch-profile lan'));
      expect(error.message, contains('cùng một mạng Wi-Fi'));
    });

    test('lỗi lạ của tầng mạng (ví dụ bắt tay TLS) vẫn thành ApiException', () async {
      DeviceInfo.current = phone;
      final error = await failWith('https://192.168.1.10:5199', const _FakeTlsException());
      expect(error.isNetworkError, isTrue);
      expect(error.message, contains('https://'));
    });
  });

  group('Giao diện', () {
    late DeviceInfo saved;
    setUp(() => saved = DeviceInfo.current);
    tearDown(() => DeviceInfo.current = saved);

    testWidgets('màn hình chào cảnh báo ngay khi điện thoại thật đang trỏ vào localhost',
        (tester) async {
      DeviceInfo.current = phone;
      SharedPreferences.setMockInitialValues({'server_url': 'http://localhost:5199'});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();

      expect(find.textContaining('không dùng được trên thiết bị này'), findsOneWidget);
      await tester.tap(find.text('Bấm để sửa địa chỉ máy chủ'));
      await tester.pumpAndSettle();
      expect(find.text('Cài đặt máy chủ'), findsOneWidget);
      // Màn hình cài đặt giải thích lý do ngay khi mở.
      expect(find.textContaining('chính điện thoại'), findsOneWidget);

      // Gõ IP đúng thì cảnh báo trong ô nhập biến mất.
      await tester.enterText(find.byType(TextField), 'http://192.168.1.10:5199');
      await tester.pump();
      expect(find.textContaining('chính điện thoại'), findsNothing);

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('Máy chủ: http://192.168.1.10:5199'), findsOneWidget);
      expect(find.text('Bấm để sửa địa chỉ máy chủ'), findsNothing);
    });

    testWidgets('màn hình chào không cảnh báo khi địa chỉ hợp lệ', (tester) async {
      DeviceInfo.current = phone;
      SharedPreferences.setMockInitialValues({'server_url': 'http://192.168.1.5:5199'});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();

      expect(find.text('Bấm để sửa địa chỉ máy chủ'), findsNothing);
      expect(find.text('Máy chủ: http://192.168.1.5:5199'), findsOneWidget);
    });

    testWidgets('lưu địa chỉ có vấn đề thì hỏi lại, chọn "Sửa lại" thì không lưu', (tester) async {
      DeviceInfo.current = phone;
      SharedPreferences.setMockInitialValues({'server_url': 'http://192.168.1.5:5199'});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cài đặt máy chủ'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'http://0.0.0.0:5199');
      await tester.pump();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(find.text('Địa chỉ này khó dùng được'), findsOneWidget);

      await tester.tap(find.text('Sửa lại'));
      await tester.pumpAndSettle();
      expect(find.text('Cài đặt máy chủ'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('server_url'), 'http://192.168.1.5:5199');

      // Ô trống thì không cho lưu.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();
      expect(prefs.getString('server_url'), 'http://192.168.1.5:5199');
    });

    testWidgets('bấm gợi ý máy ảo Android thì điền sẵn địa chỉ', (tester) async {
      DeviceInfo.current = emulator;
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Cài đặt máy chủ'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'http://localhost:5199');
      await tester.pump();
      expect(find.textContaining('chính máy ảo'), findsOneWidget);

      await tester.tap(find.text('http://10.0.2.2:5199'));
      await tester.pump();
      expect(find.widgetWithText(TextField, 'http://10.0.2.2:5199'), findsOneWidget);
      expect(find.textContaining('chính máy ảo'), findsNothing);
    });
  });
}

class _FakeTlsException implements Exception {
  const _FakeTlsException();
}
