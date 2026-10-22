import 'package:ambulance_way/app.dart';
import 'package:ambulance_way/core/api_client.dart';
import 'package:ambulance_way/models/driver_models.dart';
import 'package:ambulance_way/models/patient_models.dart';
import 'package:ambulance_way/screens/driver/incoming_sos_dialog.dart';
import 'package:ambulance_way/screens/patient/rating_view.dart';
import 'package:ambulance_way/state/driver_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/fakes.dart';

void main() {
  group('Màn hình chào', () {
    testWidgets('chưa đăng nhập thì cho chọn vai trò và hiện địa chỉ máy chủ đã lưu',
        (tester) async {
      SharedPreferences.setMockInitialValues({'server_url': 'http://192.168.1.5:5199'});

      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();

      expect(find.text('Tôi cần cấp cứu'), findsOneWidget);
      expect(find.text('Tôi là tài xế xe cấp cứu'), findsOneWidget);
      expect(find.text('Máy chủ: http://192.168.1.5:5199'), findsOneWidget);
    });

    testWidgets('form đăng nhập tài xế bắt buộc nhập đủ tài khoản và mật khẩu', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tôi là tài xế xe cấp cứu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ĐĂNG NHẬP'));
      await tester.pump();

      expect(find.text('Nhập tên đăng nhập'), findsOneWidget);
      expect(find.text('Nhập mật khẩu'), findsOneWidget);
    });

    testWidgets('form bệnh nhân từ chối số điện thoại sai định dạng', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(const AmbulanceWayApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tôi cần cấp cứu'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '12345');
      await tester.tap(find.text('NHẬN MÃ OTP'));
      await tester.pump();

      expect(find.text('Số điện thoại gồm 9-11 chữ số'), findsOneWidget);
    });
  });

  group('Hộp thoại SOS mới', () {
    const request = PendingCase(
      caseId: 7,
      address: '268 Lý Thường Kiệt',
      summary: 'Tai nạn giao thông: Ngã xe',
      location: LatLng(10.762622, 106.660172),
    );

    late DriverController controller;
    bool? result;

    Future<void> open(WidgetTester tester) async {
      controller = DriverController(
        api: ApiClient(baseUrl: 'http://server'),
        routing: offlineRouting(),
        location: NoGpsLocationService(),
        hubFactory: (_) => FakeHub(),
      )..pending = [request];
      addTearDown(controller.dispose);
      result = null;

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDialog<bool>(
                context: context,
                builder: (_) => IncomingSosDialog(controller: controller, request: request),
              );
            },
            child: const Text('mở'),
          ),
        ),
      ));
      await tester.tap(find.text('mở'));
      await tester.pumpAndSettle();
    }

    testWidgets('đếm ngược 15 giây rồi tự đóng, ca vẫn nằm trong hàng chờ', (tester) async {
      await open(tester);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('268 Lý Thường Kiệt'), findsOneWidget);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('10'), findsOneWidget);

      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();

      expect(find.byType(IncomingSosDialog), findsNothing);
      expect(result, isFalse);
      expect(controller.pending, hasLength(1));
    });

    testWidgets('bấm NHẬN CA NGAY trả về true', (tester) async {
      await open(tester);

      await tester.tap(find.text('NHẬN CA NGAY'));
      await tester.pumpAndSettle();

      expect(result, isTrue);
    });

    testWidgets('ca bị tài xế khác nhận thì hộp thoại tự đóng', (tester) async {
      await open(tester);

      controller.dismissPending(7);
      await tester.pumpAndSettle();

      expect(find.byType(IncomingSosDialog), findsNothing);
      expect(result, isFalse);
    });
  });

  group('Form đánh giá', () {
    testWidgets('gửi đúng số sao người dùng chọn cho từng tiêu chí', (tester) async {
      RatingForm? submitted;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: RatingView(
            onSubmit: (form) async {
              submitted = form;
              return null;
            },
            onSkip: () {},
          ),
        ),
      ));

      // Hàng thứ 2 là "Thời gian xe đến": chọn 3 sao; hàng đầu (tổng thể) chọn 4 sao.
      await tester.tap(find.byTooltip('3 sao').at(1));
      await tester.tap(find.byTooltip('4 sao').at(0));
      await tester.pump();

      // Ô ý kiến nhiều dòng cũng là một vùng cuộn nên phải chỉ rõ cuộn danh sách ngoài.
      await tester.scrollUntilVisible(find.text('GỬI ĐÁNH GIÁ'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.enterText(find.byType(TextField), '  Xe đến hơi chậm ');
      await tester.tap(find.text('GỬI ĐÁNH GIÁ'));
      await tester.pumpAndSettle();

      expect(submitted!.overall, 4);
      expect(submitted!.responseTime, 3);
      expect(submitted!.driverAttitude, 5);
      expect(submitted!.comment, 'Xe đến hơi chậm');
      expect(find.text('Cảm ơn bạn đã đánh giá!'), findsOneWidget);
    });
  });
}
