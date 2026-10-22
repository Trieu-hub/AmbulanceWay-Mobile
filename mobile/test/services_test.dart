import 'dart:convert';

import 'package:ambulance_way/core/api_client.dart';
import 'package:ambulance_way/core/geo.dart';
import 'package:ambulance_way/models/session.dart';
import 'package:ambulance_way/services/auth_service.dart';
import 'package:ambulance_way/services/driver_api.dart';
import 'package:ambulance_way/services/geocoding_service.dart';
import 'package:ambulance_way/services/routing_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

http.Response _jsonResponse(Object body, [int status = 200]) => http.Response.bytes(
      utf8.encode(jsonEncode(body)),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  group('ApiClient', () {
    test('chuẩn hóa địa chỉ máy chủ người dùng nhập', () {
      expect(ApiClient.normalizeBaseUrl(' 192.168.1.10:5199/ '), 'http://192.168.1.10:5199');
      expect(ApiClient.normalizeBaseUrl('https://example.com//'), 'https://example.com');
      expect(ApiClient.normalizeBaseUrl('http://localhost:5199'), 'http://localhost:5199');
    });

    test('gửi kèm token và trả về JSON đã giải mã', () async {
      late http.Request seen;
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((request) async {
          seen = request;
          return _jsonResponse({'ok': true});
        }),
      )..token = 'jwt-123';

      final data = await api.post('/api/x', body: {'a': 1});

      expect(data, {'ok': true});
      expect(seen.url.toString(), 'http://server/api/x');
      expect(seen.headers['Authorization'], 'Bearer jwt-123');
      expect(jsonDecode(seen.body), {'a': 1});
    });

    test('lấy câu báo lỗi tiếng Việt từ body dù viết hoa hay thường', () async {
      Future<ApiException> failWith(Object body, int status) async {
        final api = ApiClient(
          baseUrl: 'http://server',
          httpClient: MockClient((_) async => _jsonResponse(body, status)),
        );
        try {
          await api.get('/x');
        } on ApiException catch (error) {
          return error;
        }
        fail('phải ném ApiException');
      }

      expect((await failWith({'message': 'OTP sai'}, 400)).message, 'OTP sai');
      expect((await failWith({'Success': false, 'Message': 'Sai mật khẩu'}, 401)).message,
          'Sai mật khẩu');
      // ProblemDetails của [ApiController] khi model không hợp lệ.
      expect(
          (await failWith({
            'title': 'One or more validation errors occurred.',
            'errors': {
              'PatientAddress': ['The PatientAddress field is required.']
            }
          }, 400))
              .message,
          'The PatientAddress field is required.');
      expect((await failWith('Tên bệnh viện là bắt buộc', 400)).message, 'Tên bệnh viện là bắt buộc');
      expect((await failWith({}, 403)).statusCode, 403);
    });

    test('401 khi có token thì báo hết phiên; 401 lúc đăng nhập thì không', () async {
      var rejected = 0;
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((_) async => _jsonResponse({'Message': 'x'}, 401)),
      )..onSessionRejected = () => rejected++;

      await expectLater(api.post('/api/auth/login'), throwsA(isA<ApiException>()));
      expect(rejected, 0);

      api.token = 'expired';
      await expectLater(api.get('/api/duty/current'), throwsA(isA<ApiException>()));
      expect(rejected, 1);
    });

    test('không kết nối được thì báo lỗi mạng, không có mã trạng thái', () async {
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((_) async => throw http.ClientException('refused')),
      );

      await expectLater(
        api.get('/x'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)
            .having((e) => e.message, 'message', contains('http://server'))),
      );
    });
  });

  group('AuthService', () {
    test('tài khoản không phải tài xế bị từ chối ngay trên app', () async {
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((_) async => _jsonResponse({
              'Success': true,
              'Token': 't',
              'User': {'Username': 'admin', 'Role': 'ADMIN'}
            })),
      );

      await expectLater(
        AuthService(api).loginDriver('admin', '123'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('không phải tài xế'))),
      );
    });

    test('đăng nhập tài xế trả về phiên với tên đăng nhập do máy chủ chuẩn hóa', () async {
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((_) async => _jsonResponse({
              'Success': true,
              'Token': 'jwt',
              'User': {'Username': 'driver1', 'Role': 'DRIVER'}
            })),
      );

      final session = await AuthService(api).loginDriver(' DRIVER1 ', 'x');

      expect(session.role, UserRole.driver);
      expect(session.token, 'jwt');
      expect(session.loginName, 'driver1');
    });

    test('xác thực OTP trả về phiên bệnh nhân kèm mã hồ sơ', () async {
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((_) async => _jsonResponse(
            {'success': true, 'verified': true, 'profileId': 4, 'fullName': 'Lê C', 'token': 'p'})),
      );

      final session = await AuthService(api).verifyPatientOtp('0900000000', '123456');

      expect(session.role, UserRole.patient);
      expect(session.patientProfileId, 4);
      expect(session.displayName, 'Lê C');
    });

    test('backend cũ chưa trả token thì báo rõ cần cập nhật', () async {
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((_) async => _jsonResponse({'success': true, 'verified': true})),
      );

      await expectLater(
        AuthService(api).verifyPatientOtp('0900000000', '123456'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('cập nhật backend'))),
      );
    });
  });

  group('DriverApi', () {
    test('hoàn thành ca chỉ gửi quãng đường khi có số liệu', () async {
      final bodies = <Map<String, dynamic>>[];
      final api = ApiClient(
        baseUrl: 'http://server',
        httpClient: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return _jsonResponse({'success': true});
        }),
      );
      final driverApi = DriverApi(api);

      await driverApi.updateCaseStatus(3, 'COMPLETED', distanceKm: 4.2, durationMinutes: 12);
      await driverApi.updateCaseStatus(3, 'PICKED_UP');

      expect(bodies[0], {'Status': 'COMPLETED', 'DistanceKm': 4.2, 'DurationMinutes': 12});
      expect(bodies[1], {'Status': 'PICKED_UP'});
    });
  });

  group('RoutingService', () {
    const from = LatLng(10.762622, 106.660172);
    const to = LatLng(10.7575, 106.6595);

    final osrmBody = {
      'code': 'Ok',
      'routes': [
        {
          'distance': 1840.5,
          'duration': 312.0,
          'geometry': {
            'type': 'LineString',
            'coordinates': [
              [106.660172, 10.762622],
              [106.6601, 10.76],
              [106.6595, 10.7575],
            ]
          },
          'legs': [
            {
              'steps': [
                {
                  'name': 'Lý Thường Kiệt',
                  'distance': 300.0,
                  'maneuver': {'type': 'depart', 'modifier': 'right'}
                },
                {
                  'name': 'Nguyễn Chí Thanh',
                  'distance': 1540.5,
                  'maneuver': {'type': 'turn', 'modifier': 'left'}
                },
                {
                  'name': '',
                  'distance': 0.0,
                  'maneuver': {'type': 'arrive', 'modifier': 'right'}
                },
              ]
            }
          ]
        }
      ]
    };

    test('đọc lộ trình OSRM: đổi [kinh độ, vĩ độ] thành LatLng và dịch chỉ dẫn', () async {
      late Uri requested;
      final service = RoutingService(
        httpClient: MockClient((request) async {
          requested = request.url;
          return _jsonResponse(osrmBody);
        }),
      );

      final plan = await service.route(from, to);

      // OSRM nhận tọa độ theo thứ tự kinh độ trước, vĩ độ sau.
      expect(requested.path, '/route/v1/driving/106.660172,10.762622;106.6595,10.7575');
      expect(plan.isEstimate, isFalse);
      expect(plan.points, hasLength(3));
      expect(plan.points.first, from);
      expect(plan.points.last, to);
      expect(plan.distanceKm, closeTo(1.8405, 1e-9));
      expect(plan.durationMinutes, 5);
      expect(plan.steps.map((step) => step.instruction), [
        'Xuất phát trên Lý Thường Kiệt',
        'Rẽ trái vào Nguyễn Chí Thanh',
        'Đến nơi',
      ]);
    });

    test('OSRM lỗi hoặc mất mạng thì ước lượng theo đường thẳng thay vì ném lỗi', () async {
      for (final client in [
        MockClient((_) async => http.Response('Too Many Requests', 429)),
        MockClient((_) async => _jsonResponse({'code': 'NoRoute', 'routes': <Object>[]})),
        MockClient((_) async => throw http.ClientException('offline')),
        MockClient((_) async => http.Response('<html>', 200)),
      ]) {
        final plan = await RoutingService(httpClient: client).route(from, to);

        expect(plan.isEstimate, isTrue);
        expect(plan.points, [from, to]);
        expect(plan.distanceKm, closeTo(haversineKm(from, to) * 1.3, 1e-9));
        expect(plan.durationMinutes, greaterThanOrEqualTo(1));
        expect(plan.steps, isEmpty);
      }
    });
  });

  group('GeocodingService', () {
    test('rút gọn địa chỉ Nominatim: bỏ mã bưu chính và tên nước', () {
      final address = GeocodingService.shortAddress({
        'display_name':
            '268, Lý Thường Kiệt, Phường 14, Quận 10, Thành phố Hồ Chí Minh, 72000, Việt Nam'
      });

      expect(address, '268, Lý Thường Kiệt, Phường 14, Quận 10, Thành phố Hồ Chí Minh');
      expect(GeocodingService.shortAddress({'error': 'Unable to geocode'}), isNull);
    });
  });

  group('geo', () {
    test('haversine: một độ vĩ tuyến dài khoảng 111,19 km', () {
      const a = LatLng(10, 106);
      const b = LatLng(11, 106);

      expect(haversineKm(a, b), closeTo(111.19, 0.01));
      expect(haversineKm(b, a), closeTo(111.19, 0.01));
      expect(haversineKm(a, a), 0);
    });

    test('ước lượng thời gian theo 25 km/h, tối thiểu 1 phút', () {
      expect(estimateMinutes(0.1), 1);
      expect(estimateMinutes(5), 12);
      expect(estimateMinutes(25), 60);
    });

    test('định dạng hiển thị', () {
      expect(formatDistance(0.85), '850 m');
      expect(formatDistance(3.42), '3,4 km');
      expect(formatMeters(1540.5), '1,5 km');
      expect(formatMinutes(45), '45 phút');
      expect(formatMinutes(60), '1 giờ');
      expect(formatMinutes(95), '1 giờ 35 phút');
      expect(formatDateTime(DateTime(2026, 3, 5, 7, 9)), '07:09 05/03/2026');
    });
  });
}
