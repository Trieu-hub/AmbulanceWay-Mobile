import 'package:ambulance_way/models/patient_models.dart';
import 'package:ambulance_way/state/patient_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fakes.dart';

const _spot = LatLng(10.762622, 106.660172);

Map<String, dynamic> _snapshot(
  String status, {
  int id = 21,
  Map<String, dynamic>? driver,
  Map<String, dynamic>? driverLocation,
  Map<String, dynamic>? hospital,
  bool hasRated = false,
}) =>
    {
      'id': id,
      'status': status,
      'emergencyType': 'Khó thở cấp tính',
      'description': 'tím tái',
      'patientAddress': '268 Lý Thường Kiệt',
      'patientLat': _spot.latitude,
      'patientLng': _spot.longitude,
      'createdAt': '2026-10-12T12:00:00Z',
      'driver': driver,
      'driverLocation': driverLocation,
      'hospital': hospital,
      'hasRated': hasRated,
    };

const _driver = {
  'username': 'drv1',
  'name': 'Nguyễn Văn Tài',
  'vehicle': '51A-123.45',
  'phone': '0900000001',
};

void main() {
  late FakeBackend backend;
  FakeHub? hub;
  late PatientController controller;
  late List<PatientNotice> notices;
  late FakeNotifier notifier;

  // Trạng thái của backend giả.
  late Object activeCase;
  late Map<String, dynamic> caseState;

  PatientController build({int? skippedRatingCaseId}) => PatientController(
        api: backend.api,
        profileId: 4,
        skippedRatingCaseId: skippedRatingCaseId,
        hubFactory: (_) => hub = FakeHub(),
        notifier: notifier,
      );

  setUp(() {
    backend = FakeBackend();
    hub = null;
    activeCase = {'hasCase': false};
    caseState = _snapshot('PENDING');
    notifier = FakeNotifier();

    backend.routes.addAll({
      'GET /api/mobile/patient/me': (_) => {
            'id': 4,
            'fullName': 'Lê Thị C',
            'phoneNumber': '0912345678',
            'birthDate': '1990-05-20T00:00:00',
            'gender': 'Nữ',
          },
      'GET /api/mobile/patient/cases/active': (_) => activeCase,
      'POST /api/Sos': (_) => {'success': true, 'caseId': 21},
      'GET /api/mobile/patient/cases/21': (_) => caseState,
      'POST /api/mobile/patient/cases/21/rating': (_) => {'success': true, 'ratingId': 1},
    });

    controller = build();
    notices = [];
    controller.notices.listen(notices.add);
  });

  tearDown(() => controller.dispose());

  Future<void> sendSos() async {
    await controller.init();
    expect(
      await controller.sendSos(
        emergencyType: 'Khó thở cấp tính',
        description: 'tím tái',
        address: '268 Lý Thường Kiệt',
        location: _spot,
      ),
      isNull,
    );
    await pumpEventQueue();
  }

  test('chưa có ca: ở màn hình gửi SOS, không mở kết nối realtime', () async {
    await controller.init();

    expect(controller.profile!.fullName, 'Lê Thị C');
    expect(controller.activeCase, isNull);
    expect(hub, isNull);
  });

  test('gửi SOS: gửi đúng dữ liệu, chuyển sang theo dõi và vào nhóm của ca', () async {
    await sendSos();

    expect(backend.lastBody('POST /api/Sos'), {
      'EmergencyType': 'Khó thở cấp tính',
      'Description': 'tím tái',
      'PatientProfileId': 4,
      'PatientLat': _spot.latitude,
      'PatientLng': _spot.longitude,
      'PatientAddress': '268 Lý Thường Kiệt',
    });
    expect(controller.activeCase!.id, 21);
    expect(controller.activeCase!.step, CaseStep.sent);
    expect(hub!.calls('JoinCase'), [
      [21]
    ]);
  });

  test('gửi SOS thất bại thì ở lại màn hình gửi và báo lý do', () async {
    backend.routes['POST /api/Sos'] =
        (_) => jsonResponse({'message': 'Profile chưa được xác thực OTP'}, 400);
    await controller.init();

    final error = await controller.sendSos(
        emergencyType: 'Khác', description: 'x', address: 'y', location: _spot);

    expect(error, 'Profile chưa được xác thực OTP');
    expect(controller.activeCase, isNull);
    expect(controller.sending, isFalse);
  });

  test('theo dõi realtime qua từng bước của ca', () async {
    await sendSos();

    // Tài xế nhận ca
    caseState = _snapshot('ACCEPTED', driver: _driver);
    hub!.emit('CaseAccepted', {
      'caseId': 21,
      'driverName': 'Nguyễn Văn Tài',
      'vehicle': '51A-123.45',
      'phone': '0900000001',
    });
    await pumpEventQueue();
    expect(controller.activeCase!.step, CaseStep.accepted);
    expect(controller.activeCase!.driverName, 'Nguyễn Văn Tài');
    expect(controller.activeCase!.driverPhone, '0900000001');
    expect(notices.last.message, contains('Nguyễn Văn Tài đã nhận ca'));

    // Vị trí xe và ETA
    hub!.emit('DriverLocationUpdate', {'username': 'drv1', 'lat': 10.77, 'lng': 106.67});
    hub!.emit('EtaUpdated', {'caseId': 21, 'distanceKm': 1.25, 'durationMinutes': 4});
    expect(controller.activeCase!.driverLocation, const LatLng(10.77, 106.67));
    expect(controller.etaMinutes, 4);
    expect(controller.etaKm, 1.25);

    // Đã đón bệnh nhân: ETA tới chỗ bệnh nhân không còn đúng nữa
    caseState = _snapshot('PICKED_UP', driver: _driver);
    hub!.emit('CaseStatusUpdated', {'caseId': 21, 'status': 'PICKED_UP'});
    await pumpEventQueue();
    expect(controller.activeCase!.step, CaseStep.pickedUp);
    expect(controller.etaMinutes, isNull);
    expect(controller.activeCase!.driverLocation, const LatLng(10.77, 106.67),
        reason: 'vị trí xe realtime phải được giữ lại');

    // Chốt bệnh viện
    hub!.emit('HospitalConfirmed', {
      'hospitalName': 'BV Gia Định',
      'hospitalLat': 10.801,
      'hospitalLng': 106.691,
      'assignedRoom': 'Phòng cấp cứu 2',
      'status': 'DELIVERING',
    });
    await pumpEventQueue();
    expect(controller.activeCase!.step, CaseStep.delivering);
    expect(controller.activeCase!.hospital!.name, 'BV Gia Định');
    expect(controller.activeCase!.hospital!.assignedRoom, 'Phòng cấp cứu 2');
    expect(notices.last.message, contains('BV Gia Định'));

    // Hoàn thành: ngừng theo dõi, chờ đánh giá
    hub!.emit('CaseStatusUpdated', {'caseId': 21, 'status': 'COMPLETED'});
    await pumpEventQueue();
    expect(controller.activeCase!.isCompleted, isTrue);
    expect(hub!.stopped, isTrue);
  });

  test('sự kiện của ca khác không làm đổi ca đang theo dõi', () async {
    await sendSos();

    hub!.emit('CaseAccepted', {'caseId': 99, 'driverName': 'Người Lạ', 'vehicle': 'X'});
    hub!.emit('CaseStatusUpdated', {'caseId': 99, 'status': 'COMPLETED'});
    hub!.emit('EtaUpdated', {'caseId': 99, 'distanceKm': 9.0, 'durationMinutes': 30});

    expect(controller.activeCase!.step, CaseStep.sent);
    expect(controller.activeCase!.hasDriver, isFalse);
    expect(controller.etaMinutes, isNull);
  });

  test('đọc lại từ máy chủ bù cho sự kiện bị lỡ', () async {
    await sendSos();

    // App rớt mạng nên lỡ CaseAccepted; lần đọc định kỳ sau vẫn thấy tài xế và vị trí xe.
    caseState = _snapshot('ACCEPTED',
        driver: _driver, driverLocation: {'lat': 10.765, 'lng': 106.662});
    await controller.refresh();
    await pumpEventQueue();

    expect(controller.activeCase!.step, CaseStep.accepted);
    expect(controller.activeCase!.vehicle, '51A-123.45');
    expect(controller.activeCase!.driverLocation, const LatLng(10.765, 106.662));
    expect(notices.single.message, contains('đã nhận ca'));
  });

  test('mở lại app khi ca đang diễn ra thì theo dõi tiếp', () async {
    activeCase = {'hasCase': true, 'case': _snapshot('ACCEPTED', driver: _driver)};
    caseState = _snapshot('ACCEPTED', driver: _driver);

    await controller.init();
    await pumpEventQueue();

    expect(controller.activeCase!.step, CaseStep.accepted);
    expect(hub!.calls('JoinCase'), [
      [21]
    ]);
  });

  test('gửi đánh giá xong thì quay về màn hình gửi SOS', () async {
    activeCase = {'hasCase': true, 'case': _snapshot('COMPLETED', driver: _driver)};
    await controller.init();
    expect(controller.activeCase!.isCompleted, isTrue);
    expect(hub, isNull, reason: 'ca đã xong thì không cần kết nối realtime');

    final error = await controller.submitRating(
        const RatingForm(overall: 4, responseTime: 3, comment: 'Xe đến hơi chậm'));

    expect(error, isNull);
    expect(backend.lastBody('POST /api/mobile/patient/cases/21/rating'), {
      'OverallRating': 4,
      'ResponseTimeRating': 3,
      'DriverAttitudeRating': 5,
      'VehicleConditionRating': 5,
      'SituationHandlingRating': 5,
      'Comment': 'Xe đến hơi chậm',
    });
    expect(controller.activeCase, isNull);
  });

  test('ca đã bấm "Bỏ qua" đánh giá không hiện lại ở lần mở app sau', () async {
    activeCase = {'hasCase': true, 'case': _snapshot('COMPLETED', driver: _driver)};
    controller.dispose();
    controller = build(skippedRatingCaseId: 21);

    await controller.init();

    expect(controller.activeCase, isNull);
  });

  test('gửi đánh giá lỗi thì giữ nguyên form để thử lại', () async {
    activeCase = {'hasCase': true, 'case': _snapshot('COMPLETED', driver: _driver)};
    backend.routes['POST /api/mobile/patient/cases/21/rating'] =
        (_) => jsonResponse({'message': 'Ca này đã được đánh giá rồi'}, 400);
    await controller.init();

    final error = await controller.submitRating(const RatingForm());

    expect(error, 'Ca này đã được đánh giá rồi');
    expect(controller.activeCase, isNotNull);
  });

  test('hủy SOS khi chưa có xe đón: gửi lý do, quay về màn hình gửi SOS', () async {
    backend.routes['POST /api/mobile/patient/cases/21/cancel'] = (_) => {'success': true};
    await sendSos();
    expect(controller.canCancel, isTrue);

    final error = await controller.cancelCase(reason: 'Gửi nhầm yêu cầu');
    await pumpEventQueue();

    expect(error, isNull);
    expect(backend.lastBody('POST /api/mobile/patient/cases/21/cancel'), {'Reason': 'Gửi nhầm yêu cầu'});
    expect(controller.activeCase, isNull);
    expect(hub!.stopped, isTrue);
    expect(notices.last.message, contains('Đã hủy'));
  });

  test('không hủy được khi xe đã đón: báo lỗi của máy chủ, giữ màn hình theo dõi', () async {
    backend.routes['POST /api/mobile/patient/cases/21/cancel'] =
        (_) => jsonResponse({'message': 'Xe đã đón bệnh nhân, không thể hủy'}, 400);
    await sendSos();
    caseState = _snapshot('PICKED_UP', driver: _driver);

    final error = await controller.cancelCase(reason: 'Lý do khác');
    await pumpEventQueue();

    expect(error, contains('không thể hủy'));
    expect(controller.activeCase!.step, CaseStep.pickedUp);
    expect(controller.canCancel, isFalse);
  });

  test('sửa hồ sơ: gửi dữ liệu mới (không gửi số điện thoại) và cập nhật hồ sơ đang hiển thị', () async {
    backend.routes['PUT /api/mobile/patient/me'] = (request) => {
          'id': 4,
          'fullName': 'Lê Thị Cúc',
          'phoneNumber': '0912345678',
          'drugAllergies': 'Penicillin',
        };
    await controller.init();

    final error = await controller.updateProfile(PatientRegistration(
      fullName: 'Lê Thị Cúc',
      phoneNumber: '0912345678',
      birthDate: DateTime(1990, 5, 20),
      gender: 'Nữ',
      permanentAddress: 'Quận 5',
      emergencyContactName: 'Lê Văn D',
      emergencyContactPhone: '0900000002',
      drugAllergies: 'Penicillin',
    ));

    expect(error, isNull);
    final body = backend.lastBody('PUT /api/mobile/patient/me');
    expect(body.containsKey('PhoneNumber'), isFalse);
    expect(body['FullName'], 'Lê Thị Cúc');
    expect(body['BirthDate'], '1990-05-20T00:00:00');
    expect(controller.profile!.fullName, 'Lê Thị Cúc');
    expect(controller.profile!.drugAllergies, 'Penicillin');
  });

  test('gửi SOS thì xin quyền thông báo; trạng thái đổi thì có thông báo hệ thống', () async {
    await sendSos();
    caseState = _snapshot('ACCEPTED', driver: _driver);
    await controller.refresh();

    expect(notifier.permissionRequests, 1);
    expect(notifier.shown.single.$1, 'info');
    expect(notifier.shown.single.$4, contains('Nguyễn Văn Tài'));
  });
}
