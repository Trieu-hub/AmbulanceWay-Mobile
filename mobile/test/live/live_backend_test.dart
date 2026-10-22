// Kiểm thử đầu-cuối với backend thật (REST + SignalR), không qua giao diện.
//
// Mặc định bị bỏ qua. Để chạy, bật backend rồi:
//   flutter test test/live --dart-define=API_BASE=http://localhost:5199
//
// Test tạo dữ liệu thật (1 tài xế, 1 bệnh nhân, 1 bệnh viện, 1 ca cấp cứu) nên chỉ
// chạy với cơ sở dữ liệu thử nghiệm.

import 'package:ambulance_way/core/api_client.dart';
import 'package:ambulance_way/core/json_reader.dart';
import 'package:ambulance_way/models/driver_models.dart';
import 'package:ambulance_way/models/patient_models.dart';
import 'package:ambulance_way/services/auth_service.dart';
import 'package:ambulance_way/services/driver_api.dart';
import 'package:ambulance_way/services/hub_client.dart';
import 'package:ambulance_way/state/driver_controller.dart';
import 'package:ambulance_way/state/patient_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import '../support/fakes.dart';

const String _apiBase = String.fromEnvironment('API_BASE');

Future<void> _waitFor(String what, bool Function() condition,
    {Duration timeout = const Duration(seconds: 15)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Quá $timeout mà chưa thấy: $what');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

void main() {
  test(
    'bệnh nhân gửi SOS, tài xế nhận và hoàn thành, bệnh nhân đánh giá',
    () async {
      final suffix = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
      final username = 'live_$suffix';
      final phone = '09${suffix.padLeft(8, '0').substring(0, 8)}';
      const patientSpot = LatLng(10.762622, 106.660172);
      const driverStart = LatLng(10.7700, 106.6680);

      // --- Tài khoản
      final driverClient = ApiClient(baseUrl: _apiBase);
      final patientClient = ApiClient(baseUrl: _apiBase);
      final adminClient = ApiClient(baseUrl: _apiBase);
      addTearDown(driverClient.close);
      addTearDown(patientClient.close);
      addTearDown(adminClient.close);

      await AuthService(driverClient).registerDriver(
        username: username,
        password: 'pass123',
        fullName: 'Tài Xế Live $suffix',
        vehicleNo: '51A-$suffix',
        licenseNo: 'B2',
      );
      final driverSession = await AuthService(driverClient).loginDriver(username, 'pass123');
      driverClient.token = driverSession.token;

      final ticket = await AuthService(patientClient).registerPatient(PatientRegistration(
        fullName: 'Bệnh Nhân Live $suffix',
        phoneNumber: phone,
        birthDate: DateTime(1990, 5, 20),
        gender: 'Nữ',
        permanentAddress: '12 Nguyễn Trãi, Q1',
        medicalHistory: 'Hen suyễn',
        emergencyContactName: 'Người Thân',
        emergencyContactPhone: '0900000002',
      ));
      expect(ticket.devOtp, isNotNull, reason: 'backend V1 trả OTP để thử nghiệm');
      final patientSession =
          await AuthService(patientClient).verifyPatientOtp(phone, ticket.devOtp!);
      patientClient.token = patientSession.token;

      // --- Một bệnh viện đang nhận bệnh ở gần (tạo bằng tài khoản admin mặc định)
      final adminLogin = JsonReader.tryFrom(await adminClient
          .post('/api/auth/login', body: {'Username': 'admin', 'Password': '123'}));
      adminClient.token = adminLogin!.string('token');
      final hospitalName = 'BV Live $suffix';
      await adminClient.post('/api/Hospitals', body: {
        'Name': hospitalName,
        'Address': '1 Đường Thử, Q5',
        'Lat': 10.7600,
        'Lng': 106.6590,
        'TotalEmergencyBeds': 10,
        'AvailableEmergencyBeds': 4,
      });

      // --- Tài xế vào ca
      final driver = DriverController(
        api: driverClient,
        routing: offlineRouting(),
        location: NoGpsLocationService(),
      );
      addTearDown(driver.dispose);
      final driverEvents = <DriverEvent>[];
      driver.events.listen(driverEvents.add);

      await driver.init();
      expect(driver.profile!.username, username);
      expect(await driver.startDuty(), isNull);
      await _waitFor('tài xế kết nối SignalR', () => driver.hubStatus == HubStatus.connected);
      driver.setSimulateLocation(true);
      driver.moveSimulatedPosition(driverStart);
      // Chờ máy chủ ghi nhận vị trí để SOS được điều phối theo bán kính 5 km.
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // --- Bệnh nhân gửi SOS
      final patient = PatientController(
        api: patientClient,
        profileId: patientSession.patientProfileId!,
      );
      addTearDown(patient.dispose);

      await patient.init();
      expect(patient.activeCase, isNull);
      expect(
        await patient.sendSos(
          emergencyType: 'Khó thở cấp tính',
          description: 'Tím tái, thở gấp',
          address: '268 Lý Thường Kiệt, Q10',
          location: patientSpot,
        ),
        isNull,
      );
      final caseId = patient.activeCase!.id;

      // --- Tài xế nhận tín hiệu qua SignalR thật
      await _waitFor('SOS tới tài xế', () => driver.pending.any((c) => c.caseId == caseId));
      final incoming = driverEvents.whereType<IncomingSosEvent>().last.request;
      expect(incoming.caseId, caseId);
      expect(incoming.address, '268 Lý Thường Kiệt, Q10');
      expect(incoming.summary, 'Khó thở cấp tính: Tím tái, thở gấp');

      expect(await driver.acceptCase(incoming), isNull);
      expect(driver.mission!.phase, MissionPhase.toPatient);
      await _waitFor('hồ sơ y tế của bệnh nhân', () => driver.mission?.patient != null);
      expect(driver.mission!.patient!.medicalHistory, 'Hen suyễn');

      // --- Bệnh nhân thấy tài xế, vị trí xe và ETA
      await _waitFor('bệnh nhân thấy tài xế nhận ca',
          () => patient.activeCase?.step == CaseStep.accepted && patient.activeCase!.hasDriver);
      expect(patient.activeCase!.driverName, 'Tài Xế Live $suffix');
      expect(patient.activeCase!.vehicle, '51A-$suffix');

      const moved = LatLng(10.7660, 106.6640);
      driver.moveSimulatedPosition(moved);
      await _waitFor('vị trí xe tới bệnh nhân', () => patient.activeCase?.driverLocation == moved);
      await _waitFor('ETA tới bệnh nhân', () => patient.etaMinutes != null);

      // --- Đón bệnh nhân, chọn bệnh viện
      driver.moveSimulatedPosition(patientSpot);
      expect(await driver.markPickedUp(), isNull);
      await _waitFor('bệnh nhân thấy đã đón', () => patient.activeCase?.step == CaseStep.pickedUp);
      await _waitFor('danh sách bệnh viện',
          () => driver.hospitalOptions.any((h) => h.name == hospitalName && h.notified));

      final hospital = driver.hospitalOptions.firstWhere((h) => h.name == hospitalName);
      expect(await driver.chooseHospital(hospital), isNull);
      expect(driver.mission!.phase, MissionPhase.toHospital);
      await _waitFor(
          'bệnh nhân thấy bệnh viện',
          () =>
              patient.activeCase?.step == CaseStep.delivering &&
              patient.activeCase?.hospital?.name == hospitalName);

      // --- Hoàn thành và đánh giá
      expect(await driver.completeMission(), isNull);
      expect(driver.mission, isNull);
      await _waitFor('bệnh nhân thấy hoàn thành', () => patient.activeCase?.isCompleted ?? false);

      final trips = await DriverApi(driverClient).trips();
      expect(trips.total, 1);
      expect(trips.trips.single.hospitalName, hospitalName);
      expect(trips.trips.single.patientAddress, '268 Lý Thường Kiệt, Q10');
      expect(trips.trips.single.distanceKm, greaterThan(0));

      expect(await patient.submitRating(const RatingForm(overall: 5, comment: 'Rất nhanh')), isNull);
      expect(patient.activeCase, isNull);

      // --- Sửa hồ sơ y tế: tài xế nhận ca sau thấy thông tin mới
      expect(
        await patient.updateProfile(PatientRegistration(
          fullName: 'Bệnh Nhân Live $suffix',
          phoneNumber: phone,
          birthDate: DateTime(1990, 5, 20),
          gender: 'Nữ',
          permanentAddress: '12 Nguyễn Trãi, Q1',
          medicalHistory: 'Hen suyễn, tăng huyết áp',
          drugAllergies: 'Penicillin',
          emergencyContactName: 'Người Thân',
          emergencyContactPhone: '0900000002',
        )),
        isNull,
      );
      expect(patient.profile!.drugAllergies, 'Penicillin');

      // --- SOS thứ hai: tài xế nhận rồi bệnh nhân hủy khi xe đang tới
      expect(
        await patient.sendSos(
          emergencyType: 'Khác',
          description: 'Chóng mặt',
          address: '268 Lý Thường Kiệt, Q10',
          location: patientSpot,
        ),
        isNull,
      );
      final secondId = patient.activeCase!.id;
      await _waitFor('SOS thứ hai tới tài xế', () => driver.pending.any((c) => c.caseId == secondId));
      expect(await driver.acceptCase(driver.pending.firstWhere((c) => c.caseId == secondId)), isNull);
      await _waitFor('hồ sơ đã sửa tới tài xế', () => driver.mission?.patient?.drugAllergies == 'Penicillin');
      await _waitFor('bệnh nhân thấy tài xế nhận ca thứ hai',
          () => patient.activeCase?.step == CaseStep.accepted);
      expect(patient.canCancel, isTrue);

      expect(await patient.cancelCase(reason: 'Bệnh nhân đã ổn'), isNull);
      expect(patient.activeCase, isNull);
      await _waitFor('tài xế nhận tín hiệu hủy và gỡ nhiệm vụ', () => driver.mission == null);
      expect(
        driverEvents.whereType<DriverNoticeEvent>().any((e) => e.message.contains('Bệnh nhân đã ổn')),
        isTrue,
      );

      expect(await driver.endDuty(), isNull);
      expect(driver.onDuty, isFalse);
    },
    skip: _apiBase.isEmpty ? 'Cần --dart-define=API_BASE=http://<máy chủ>:5199' : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
