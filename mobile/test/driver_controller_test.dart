import 'package:ambulance_way/core/geo.dart';
import 'package:ambulance_way/models/driver_models.dart';
import 'package:ambulance_way/services/location_service.dart';
import 'package:ambulance_way/state/driver_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/fakes.dart';

const _station = LatLng(10.80165, 106.69796);
const _patientSpot = LatLng(10.762622, 106.660172);

Map<String, dynamic> _newTrip(int caseId, {String address = '268 Lý Thường Kiệt'}) => {
      'tripId': 0,
      'staffName': 'Hệ thống',
      'address': address,
      'hospital': 'Tai nạn giao thông: Ngã xe',
      'lat': _patientSpot.latitude,
      'lng': _patientSpot.longitude,
      'caseId': caseId,
      'driver': 'N/A',
      'etaMinutes': 15,
    };

Map<String, dynamic> _activeCase(int caseId, String status, {Map<String, dynamic>? hospital}) => {
      'hasCase': true,
      'case': {
        'caseId': caseId,
        'status': status,
        'emergencyType': 'Tai nạn giao thông',
        'description': 'Ngã xe',
        'address': '268 Lý Thường Kiệt',
        'lat': _patientSpot.latitude,
        'lng': _patientSpot.longitude,
        'patient': {
          'fullName': 'Trần B',
          'phoneNumber': '0901234567',
          'medicalHistory': 'Cao huyết áp',
        },
        'hospital': hospital,
      },
    };

const _hospitalNear = {
  'Id': 2,
  'Name': 'BV Gần',
  'Address': 'Q5',
  'Lat': 10.7575,
  'Lng': 106.6595,
  'AvailableEmergencyBeds': 5,
  'ReceptionStatus': 'OPEN',
};
const _hospitalFar = {
  'Id': 1,
  'Name': 'BV Xa',
  'Address': 'Thủ Đức',
  'Lat': 10.85,
  'Lng': 106.77,
  'AvailableEmergencyBeds': 9,
  'ReceptionStatus': 'OPEN',
};
const _hospitalFull = {
  'Id': 3,
  'Name': 'BV Hết Giường',
  'Address': 'Q10',
  'Lat': 10.7626,
  'Lng': 106.6602,
  'AvailableEmergencyBeds': 0,
  'ReceptionStatus': 'FULL',
};

void main() {
  late FakeBackend backend;
  late FakeHub hub;
  late DriverController controller;
  late List<DriverEvent> events;
  late FakeNotifier notifier;

  // Trạng thái của backend giả, các route đọc từ đây.
  late bool onDuty;
  late Object activeCase;
  late List<Map<String, dynamic>> pendingCases;

  setUp(() {
    backend = FakeBackend();
    onDuty = false;
    activeCase = {'hasCase': false};
    pendingCases = [];

    backend.routes.addAll({
      'GET /api/mobile/driver/me': (_) => {
            'username': 'drv1',
            'driverName': 'Nguyễn Văn Tài',
            'vehicle': '51A-123.45',
            'phone': '0900000001',
            'licenseNo': 'B2',
            'station': 'Bệnh viện Columbia Asia',
            'stationLat': _station.latitude,
            'stationLng': _station.longitude,
            'status': 'OFFLINE',
          },
      'GET /api/duty/current': (_) => onDuty
          ? {
              'onDuty': true,
              'duty': {'id': 1, 'startTime': '2026-10-12T01:00:00'}
            }
          : {'onDuty': false},
      'POST /api/duty/start': (_) {
        onDuty = true;
        return {'success': true, 'dutyId': 1};
      },
      'POST /api/duty/end': (_) {
        onDuty = false;
        return {'success': true};
      },
      'POST /api/mobile/driver/status': (_) => {'success': true},
      'GET /api/mobile/driver/cases/active': (_) => activeCase,
      'GET /api/mobile/driver/cases/pending': (_) => pendingCases,
      'POST /api/Sos/7/accept': (_) {
        activeCase = _activeCase(7, 'ACCEPTED');
        return {'success': true};
      },
      'PUT /api/Sos/7/status': (_) => {'success': true},
      'GET /api/Hospitals': (_) => [_hospitalFar, _hospitalFull, _hospitalNear],
      'POST /api/mobile/driver/cases/7/destination': (_) => {
            'success': true,
            'hospital': {
              'id': 2,
              'name': 'BV Gần',
              'address': 'Q5',
              'lat': 10.7575,
              'lng': 106.6595,
            },
          },
    });

    controller = DriverController(
      api: backend.api,
      routing: offlineRouting(),
      location: NoGpsLocationService(),
      hubFactory: (_) => hub = FakeHub(),
      notifier: notifier = FakeNotifier(),
    );
    events = [];
    controller.events.listen(events.add);
  });

  tearDown(() => controller.dispose());

  /// Vào ca và đặt xe tại vị trí bệnh nhân bằng chế độ mô phỏng.
  Future<void> goOnDuty() async {
    await controller.init();
    expect(await controller.startDuty(), isNull);
  }

  test('chưa vào ca: chỉ tải hồ sơ, không mở kết nối realtime', () async {
    await controller.init();

    expect(controller.loading, isFalse);
    expect(controller.profile!.username, 'drv1');
    expect(controller.onDuty, isFalse);
    expect(backend.log, isNot(contains('POST /api/mobile/driver/status')));
  });

  test('vào ca: mở ca trực, báo ONLINE và đăng ký tài xế với hub', () async {
    await goOnDuty();

    expect(controller.onDuty, isTrue);
    expect(backend.log, containsAllInOrder(['POST /api/duty/start', 'POST /api/mobile/driver/status']));
    expect(backend.lastBody('POST /api/mobile/driver/status'), {'Status': 'ONLINE'});
    expect(backend.lastBody('POST /api/duty/start'), {
      'HospitalName': 'Bệnh viện Columbia Asia',
      'StaffName': 'Nguyễn Văn Tài',
      'VehicleNo': '51A-123.45',
    });
    expect(hub.started, isTrue);
    expect(hub.calls('RegisterDriver'), [
      ['drv1']
    ]);
    // Không có GPS: bản đồ dùng vị trí trạm nhưng không gửi vị trí giả lên máy chủ.
    expect(controller.locationIssue, LocationIssue.unavailable);
    expect(controller.mapPosition, _station);
    expect(hub.calls('SendLocationUpdate'), isEmpty);
  });

  test('ca trực còn mở từ lần trước được tiếp tục khi mở lại app', () async {
    onDuty = true;
    activeCase = _activeCase(7, 'DELIVERING', hospital: {
      'id': 2,
      'name': 'BV Gần',
      'address': 'Q5',
      'lat': 10.7575,
      'lng': 106.6595,
    });

    await controller.init();
    await pumpEventQueue();

    expect(controller.onDuty, isTrue);
    expect(backend.log, isNot(contains('POST /api/duty/start')));
    expect(controller.mission!.phase, MissionPhase.toHospital);
    expect(controller.mission!.hospital!.name, 'BV Gần');
    expect(controller.route!.destination, const LatLng(10.7575, 106.6595));
  });

  test('SOS mới vào hàng chờ; lệnh kiểu cũ (caseId 0) và bản trùng bị bỏ qua', () async {
    await goOnDuty();

    hub.emit('ReceiveNewTrip', _newTrip(7));
    hub.emit('ReceiveNewTrip', _newTrip(7));
    hub.emit('ReceiveNewTrip', _newTrip(0));
    hub.emit('ReceiveNewTrip', {'targetDriver': 'drv1', 'data': <String, dynamic>{}});
    await pumpEventQueue();

    expect(controller.pending.map((item) => item.caseId), [7]);
    expect(events.whereType<IncomingSosEvent>().map((e) => e.request.caseId), [7, 7]);
  });

  test('tài xế khác nhận trước thì ca biến mất khỏi hàng chờ', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    hub.emit('ReceiveNewTrip', _newTrip(8, address: '12 Nguyễn Trãi'));

    hub.emit('CaseAlreadyTaken', {'caseId': 8, 'takenBy': 'Lê Văn Khác'});
    await pumpEventQueue();

    expect(controller.pending.map((item) => item.caseId), [7]);
    expect(events.whereType<DriverNoticeEvent>().single.message, contains('Lê Văn Khác'));
  });

  test('vào ca thì xin quyền thông báo; SOS mới hiện thông báo hệ thống (khi app chạy nền)', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    await pumpEventQueue();

    expect(notifier.permissionRequests, 1);
    expect(notifier.shown.single.$1, 'urgent');
    expect(notifier.shown.single.$2, 7);
    expect(notifier.shown.single.$4, contains('268 Lý Thường Kiệt'));
  });

  test('bệnh nhân hủy SOS: ca rời hàng chờ của các tài xế', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    hub.emit('ReceiveNewTrip', _newTrip(8, address: '12 Nguyễn Trãi'));

    hub.emit('CaseCancelled', {'CaseId': 8, 'Reason': 'Gửi nhầm yêu cầu'});
    await pumpEventQueue();

    expect(controller.pending.map((item) => item.caseId), [7]);
    expect(events.whereType<DriverNoticeEvent>().single.message, contains('#8'));
  });

  test('bệnh nhân hủy ca tài xế đang chạy tới: gỡ nhiệm vụ, báo lý do', () async {
    await goOnDuty();
    controller.setSimulateLocation(true);
    controller.moveSimulatedPosition(_station);
    hub.emit('ReceiveNewTrip', _newTrip(7));
    expect(await controller.acceptCase(controller.pending.single), isNull);
    await pumpEventQueue();
    expect(controller.mission, isNotNull);

    activeCase = {'hasCase': false};
    hub.emit('CaseCancelled', {'CaseId': 7, 'Reason': 'Bệnh nhân đã ổn'});
    await pumpEventQueue();

    expect(controller.mission, isNull);
    expect(controller.route, isNull);
    final notice = events.whereType<DriverNoticeEvent>().last;
    expect(notice.message, contains('Bệnh nhân đã ổn'));
    expect(notice.isError, isTrue);
    expect(notifier.shown.last.$3, 'Ca #7 đã bị hủy');
  });

  test('chế độ mô phỏng gửi vị trí do người dùng chấm lên máy chủ', () async {
    await goOnDuty();

    controller.setSimulateLocation(true);
    controller.moveSimulatedPosition(const LatLng(10.77, 106.67));

    expect(controller.mapPosition, const LatLng(10.77, 106.67));
    expect(hub.calls('SendLocationUpdate').last, ['drv1', 10.77, 106.67]);
  });

  test('trọn một nhiệm vụ: nhận ca → đón bệnh → chọn viện → hoàn thành', () async {
    await goOnDuty();
    controller.setSimulateLocation(true);
    controller.moveSimulatedPosition(_station);
    hub.emit('ReceiveNewTrip', _newTrip(7));

    // --- Nhận ca
    expect(await controller.acceptCase(controller.pending.single), isNull);
    await pumpEventQueue();

    expect(backend.lastBody('POST /api/Sos/7/accept'), {'DriverUsername': 'drv1'});
    expect(controller.pending, isEmpty);
    expect(controller.mission!.phase, MissionPhase.toPatient);
    expect(controller.mission!.patient!.medicalHistory, 'Cao huyết áp');
    expect(controller.route!.origin, _station);
    expect(controller.route!.destination, _patientSpot);
    final toPatientKm = haversineKm(_station, _patientSpot) * 1.3;
    expect(controller.route!.distanceKm, closeTo(toPatientKm, 1e-9));
    // Người nhà nhận ETA và vị trí xe của đúng ca này.
    expect(hub.calls('SendEtaUpdate').last.first, 7);
    expect(hub.calls('SendDriverLocationToCase').last,
        [7, 'drv1', _station.latitude, _station.longitude]);

    // Máy chủ phát CaseAlreadyTaken cho cả người vừa nhận: không được tự hủy nhiệm vụ.
    hub.emit('CaseAlreadyTaken', {'caseId': 7, 'takenBy': 'Nguyễn Văn Tài'});
    expect(controller.mission, isNotNull);

    // --- Đã đón bệnh nhân
    controller.moveSimulatedPosition(_patientSpot);
    activeCase = _activeCase(7, 'PICKED_UP');
    expect(await controller.markPickedUp(), isNull);
    await pumpEventQueue();

    expect(backend.lastBody('PUT /api/Sos/7/status'), {'Status': 'PICKED_UP'});
    expect(controller.mission!.phase, MissionPhase.pickedUp);
    expect(controller.route, isNull);
    // Chỉ bệnh viện đang nhận bệnh, gần nhất xếp trước.
    expect(controller.hospitalOptions.map((h) => h.name), ['BV Gần', 'BV Xa']);

    hub.emit('SuggestHospitals', [
      {'id': 2, 'name': 'BV Gần', 'receptionStatus': 'OPEN', 'availableEmergencyBeds': 5, 'distance': 0.57}
    ]);
    expect(controller.hospitalOptions.map((h) => h.notified), [true, false]);

    hub.emit('HospitalConfirmed', {
      'status': 'REJECTED',
      'hospitalName': 'BV Xa',
      'rejectReason': 'FULL_BEDS',
    });
    await pumpEventQueue();
    expect(controller.mission!.phase, MissionPhase.pickedUp);
    expect(events.whereType<DriverNoticeEvent>().last.message, contains('BV Xa từ chối'));

    // --- Chọn bệnh viện
    expect(await controller.chooseHospital(controller.hospitalOptions.first), isNull);

    expect(backend.lastBody('POST /api/mobile/driver/cases/7/destination'), {'HospitalId': 2});
    expect(controller.mission!.phase, MissionPhase.toHospital);
    expect(controller.mission!.hospital!.name, 'BV Gần');
    expect(controller.route!.destination, const LatLng(10.7575, 106.6595));
    final toHospitalKm = haversineKm(_patientSpot, const LatLng(10.7575, 106.6595)) * 1.3;

    // --- Hoàn thành
    activeCase = {'hasCase': false};
    expect(await controller.completeMission(), isNull);
    await pumpEventQueue();

    final body = backend.lastBody('PUT /api/Sos/7/status');
    expect(body['Status'], 'COMPLETED');
    // Quãng đường ghi vào lịch sử là tổng hai chặng: tới bệnh nhân + về viện.
    expect(body['DistanceKm'], closeTo(toPatientKm + toHospitalKm, 0.011));
    expect(body['DurationMinutes'], estimateMinutes(toPatientKm) + estimateMinutes(toHospitalKm));
    expect(controller.mission, isNull);
    expect(controller.route, isNull);
    expect(controller.hospitalOptions, isEmpty);
  });

  test('bệnh viện xác nhận qua cổng web thì lộ trình chuyển sang bệnh viện đó', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    await controller.acceptCase(controller.pending.single);
    await pumpEventQueue();
    activeCase = _activeCase(7, 'PICKED_UP');
    await controller.markPickedUp();

    // HospitalPortalController gửi Status = "ACCEPTED" (bản web cũ chờ "CONFIRMED").
    hub.emit('HospitalConfirmed', {
      'notificationId': 4,
      'status': 'ACCEPTED',
      'hospitalName': 'BV Gia Định',
      'hospitalLat': 10.801,
      'hospitalLng': 106.691,
      'hospitalAddress': 'Bình Thạnh',
      'assignedRoom': 'Phòng cấp cứu 2',
    });
    await pumpEventQueue();

    expect(controller.mission!.phase, MissionPhase.toHospital);
    expect(controller.mission!.hospital!.name, 'BV Gia Định');
    expect(controller.mission!.hospital!.assignedRoom, 'Phòng cấp cứu 2');
    expect(controller.route!.destination, const LatLng(10.801, 106.691));
    expect(events.whereType<HospitalAcceptedEvent>().single.hospital.name, 'BV Gia Định');
  });

  test('xác nhận của bệnh viện đến khi chưa đón bệnh nhân thì bỏ qua', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    await controller.acceptCase(controller.pending.single);
    await pumpEventQueue();

    hub.emit('HospitalConfirmed', {
      'status': 'ACCEPTED',
      'hospitalName': 'BV Gia Định',
      'hospitalLat': 10.801,
      'hospitalLng': 106.691,
    });

    expect(controller.mission!.phase, MissionPhase.toPatient);
    expect(controller.route!.destination, _patientSpot);
  });

  test('nhận ca thất bại: báo lý do của máy chủ và bỏ ca khỏi hàng chờ', () async {
    backend.routes['POST /api/Sos/7/accept'] =
        (_) => jsonResponse({'message': 'Ca này đã được tiếp nhận hoặc đã kết thúc.'}, 400);
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));

    final error = await controller.acceptCase(controller.pending.single);

    expect(error, 'Ca này đã được tiếp nhận hoặc đã kết thúc.');
    expect(controller.mission, isNull);
    expect(controller.pending, isEmpty);
    expect(controller.busy, isFalse);
  });

  test('máy chủ báo ca đã kết thúc khi đang làm thì nhiệm vụ được gỡ khỏi màn hình', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    await controller.acceptCase(controller.pending.single);
    await pumpEventQueue();

    // Admin vừa xóa/đóng ca: lần cập nhật kế tiếp bị từ chối và máy chủ không còn ca đang làm.
    activeCase = {'hasCase': false};
    backend.routes['PUT /api/Sos/7/status'] = (_) => jsonResponse(
        {'message': 'Ca cấp cứu này đã kết thúc, không thể cập nhật trạng thái mới.'}, 400);

    final error = await controller.markPickedUp();

    expect(error, contains('đã kết thúc'));
    expect(controller.mission, isNull);
  });

  test('không cho kết thúc ca khi còn nhiệm vụ; kết thúc được thì báo OFFLINE và ngắt hub', () async {
    await goOnDuty();
    hub.emit('ReceiveNewTrip', _newTrip(7));
    await controller.acceptCase(controller.pending.single);
    await pumpEventQueue();

    expect(await controller.endDuty(), contains('hoàn thành nhiệm vụ'));
    expect(controller.onDuty, isTrue);

    activeCase = {'hasCase': false};
    await controller.completeMission();
    expect(await controller.endDuty(), isNull);

    expect(controller.onDuty, isFalse);
    expect(backend.log, contains('POST /api/duty/end'));
    expect(backend.lastBody('POST /api/mobile/driver/status'), {'Status': 'OFFLINE'});
    expect(hub.stopped, isTrue);
  });

  test('mất tín hiệu GPS tạm thời: giữ vị trí gần nhất, có tín hiệu lại thì hết cảnh báo', () async {
    final gps = ScriptedLocationService();
    final driver = DriverController(
      api: backend.api,
      routing: offlineRouting(),
      location: gps,
      hubFactory: (_) => hub = FakeHub(),
    );
    addTearDown(driver.dispose);
    await driver.init();
    await driver.startDuty();
    await pumpEventQueue();
    expect(driver.locationIssue, isNull);

    const first = LatLng(10.77, 106.668);
    gps.positions.add(first);
    await pumpEventQueue();
    expect(driver.mapPosition, first);
    expect(hub.calls('SendLocationUpdate').last, ['drv1', 10.77, 106.668]);

    gps.positions.addError(Exception('mất tín hiệu'));
    await pumpEventQueue();
    expect(driver.locationIssue, LocationIssue.unavailable);
    expect(driver.mapPosition, first, reason: 'không được nhảy về vị trí trạm khi đã có GPS');

    const second = LatLng(10.766, 106.664);
    gps.positions.add(second);
    await pumpEventQueue();
    expect(driver.locationIssue, isNull);
    expect(driver.mapPosition, second);
  });

  test('đọc lại hàng chờ từ máy chủ, không lặp ca đang làm', () async {
    pendingCases = [
      {
        'caseId': 9,
        'status': 'PENDING',
        'emergencyType': 'Khác',
        'description': '',
        'address': 'Chợ Bến Thành',
        'lat': 10.7725,
        'lng': 106.698,
        'createdAt': '2026-10-12T12:00:00Z',
      },
      {
        'caseId': 10,
        'status': 'ASSIGNED',
        'emergencyType': 'Đột quỵ / Tai biến',
        'description': 'bất tỉnh',
        'address': 'Dinh Độc Lập',
        'lat': 10.777,
        'lng': 106.6953,
        'createdAt': '2026-10-12T12:01:00Z',
      },
    ];

    await goOnDuty();

    expect(controller.pending.map((item) => item.caseId), [9, 10]);
    expect(controller.pending.last.assignedToMe, isTrue);
    expect(controller.pending.last.summary, 'Đột quỵ / Tai biến: bất tỉnh');
  });
}
