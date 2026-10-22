import 'dart:convert';

import 'package:ambulance_way/core/json_reader.dart';
import 'package:ambulance_way/models/driver_models.dart';
import 'package:ambulance_way/models/hospital.dart';
import 'package:ambulance_way/models/patient_models.dart';
import 'package:ambulance_way/models/session.dart';
import 'package:flutter_test/flutter_test.dart';

JsonReader _json(String source) => JsonReader(jsonDecode(source) as Map<String, dynamic>);

void main() {
  group('PendingCase', () {
    test('đọc payload ReceiveNewTrip đúng như máy chủ gửi qua SignalR', () {
      // Chép từ lần chạy thật với backend hiện tại (SignalR giữ PascalCase).
      final request = PendingCase.fromRealtime(_json(
          '{"TripId":0,"StaffName":"Tai Xe","Address":"268 Lý Thường Kiệt, Q10",'
          '"Hospital":"Tai nạn giao thông: Ngã xe","Lat":10.762622,"Lng":106.660172,'
          '"CaseId":12,"Driver":"Tai Xe","EtaMinutes":3}'));

      expect(request.caseId, 12);
      expect(request.address, '268 Lý Thường Kiệt, Q10');
      expect(request.summary, 'Tai nạn giao thông: Ngã xe');
      expect(request.location.latitude, closeTo(10.762622, 1e-9));
      expect(request.location.longitude, closeTo(106.660172, 1e-9));
      expect(request.etaMinutes, 3);
    });

    test('backend bản cũ gửi camelCase vẫn đọc được', () {
      final request = PendingCase.fromRealtime(_json(
          '{"tripId":0,"address":"12 Nguyễn Trãi","hospital":"Khác","lat":10.7,"lng":106.6,'
          '"caseId":9,"etaMinutes":15}'));

      expect(request.caseId, 9);
      expect(request.address, '12 Nguyễn Trãi');
      expect(request.etaMinutes, 15);
    });

    test('lệnh điều phối kiểu cũ không có caseId cho ra caseId = 0', () {
      final request = PendingCase.fromRealtime(_json('{"targetDriver":"a","data":{}}'));

      expect(request.caseId, 0);
    });

    test('đọc phần tử của /api/mobile/driver/cases/pending', () {
      final request = PendingCase.fromApi(_json(
          '{"caseId":5,"status":"ASSIGNED","emergencyType":"Khác","description":"",'
          '"address":"x","lat":10.7,"lng":106.6,"createdAt":"2026-10-12T12:59:13.809369Z"}'));

      expect(request.caseId, 5);
      expect(request.summary, 'Khác');
      expect(request.assignedToMe, isTrue);
      expect(request.createdAt!.toUtc(), DateTime.utc(2026, 10, 12, 12, 59, 13, 809, 369));
    });

    test('buildSummary ghép loại khẩn cấp và mô tả', () {
      expect(PendingCase.buildSummary('Đột quỵ', 'bất tỉnh'), 'Đột quỵ: bất tỉnh');
      expect(PendingCase.buildSummary('Đột quỵ', ''), 'Đột quỵ');
      expect(PendingCase.buildSummary('', 'bất tỉnh'), 'bất tỉnh');
      expect(PendingCase.buildSummary('', ''), 'Ca cấp cứu');
    });
  });

  group('Mission', () {
    test('khôi phục ca đang chạy tới bệnh nhân kèm hồ sơ y tế', () {
      final mission = Mission.fromApi(_json(
          '{"caseId":3,"status":"ACCEPTED","emergencyType":"Khó thở cấp tính","description":"tím tái",'
          '"address":"12 Nguyễn Trãi","lat":10.76,"lng":106.66,'
          '"patient":{"fullName":"Trần B","phoneNumber":"0901234567","gender":"Nữ",'
          '"birthDate":"1990-05-20T00:00:00","medicalHistory":"Hen suyễn","drugAllergies":null},'
          '"hospital":null}'));

      expect(mission.phase, MissionPhase.toPatient);
      expect(mission.summary, 'Khó thở cấp tính: tím tái');
      expect(mission.patient!.fullName, 'Trần B');
      expect(mission.patient!.medicalHistory, 'Hen suyễn');
      expect(mission.patient!.drugAllergies, isNull);
      expect(mission.hospital, isNull);
    });

    test('trạng thái máy chủ quyết định chặng của nhiệm vụ', () {
      expect(Mission.phaseFromStatus('ACCEPTED', hasHospital: false), MissionPhase.toPatient);
      expect(Mission.phaseFromStatus('PICKED_UP', hasHospital: false), MissionPhase.pickedUp);
      expect(Mission.phaseFromStatus('DELIVERING', hasHospital: true), MissionPhase.toHospital);
      // DELIVERING mà chưa ghi bệnh viện: phải cho tài xế chọn lại chứ không dẫn đường tới tọa độ rỗng.
      expect(Mission.phaseFromStatus('DELIVERING', hasHospital: false), MissionPhase.pickedUp);
    });
  });

  group('PatientInfo.age', () {
    test('tính tuổi tròn năm', () {
      final now = DateTime.now();
      final justTurned30 = PatientInfo(
          fullName: 'A', phoneNumber: '0', birthDate: DateTime(now.year - 30, now.month, now.day));
      final almost30 = PatientInfo(
          fullName: 'A',
          phoneNumber: '0',
          birthDate: DateTime(now.year - 30, now.month, now.day).add(const Duration(days: 1)));

      expect(justTurned30.age, 30);
      expect(almost30.age, 29);
      expect(const PatientInfo(fullName: 'A', phoneNumber: '0').age, isNull);
    });
  });

  group('Hospital', () {
    test('đọc GET /api/Hospitals (PascalCase)', () {
      final hospital = Hospital.fromJson(_json(
          '{"Id":1,"Name":"BV Chợ Rẫy","Address":"Q5","Lat":10.7575,"Lng":106.6595,'
          '"Phone":"02838550000","AvailableEmergencyBeds":5,"ReceptionStatus":"OPEN"}'));

      expect(hospital.id, 1);
      expect(hospital.name, 'BV Chợ Rẫy');
      expect(hospital.availableBeds, 5);
      expect(hospital.isOpen, isTrue);
    });

    test('bệnh viện FULL hoặc CLOSED không được coi là đang nhận bệnh', () {
      Hospital withStatus(String status) => Hospital.fromJson(
          _json('{"Id":1,"Name":"BV","Lat":1,"Lng":1,"ReceptionStatus":"$status"}'));

      expect(withStatus('FULL').isOpen, isFalse);
      expect(withStatus('CLOSED').isOpen, isFalse);
    });

    test('đọc payload HospitalConfirmed của SignalR', () {
      final hospital = Hospital.fromConfirmation(_json(
          '{"notificationId":4,"status":"ACCEPTED","hospitalName":"BV Gia Định",'
          '"hospitalLat":10.801,"hospitalLng":106.691,"hospitalAddress":"Bình Thạnh",'
          '"assignedRoom":"Phòng cấp cứu 2"}'));

      expect(hospital.name, 'BV Gia Định');
      expect(hospital.location.latitude, closeTo(10.801, 1e-9));
      expect(hospital.assignedRoom, 'Phòng cấp cứu 2');
    });
  });

  group('CaseSnapshot', () {
    test('đọc ảnh chụp ca đã có tài xế và bệnh viện', () {
      final snapshot = CaseSnapshot.fromJson(_json(
          '{"id":9,"status":"DELIVERING","emergencyType":"Khác","description":"d",'
          '"patientAddress":"a","patientLat":10.76,"patientLng":106.66,'
          '"createdAt":"2026-10-12T12:59:13.7396777Z",'
          '"driver":{"username":"drv","name":"Tài Xế","vehicle":"51A-1","phone":"0900000001"},'
          '"driverLocation":{"lat":10.7605,"lng":106.6615,"updatedAt":"2026-10-12T13:00:00Z"},'
          '"hospital":{"id":2,"name":"BV","address":"Q5","lat":10.75,"lng":106.65,"assignedRoom":"P2"},'
          '"hasRated":false}'));

      expect(snapshot.step, CaseStep.delivering);
      expect(snapshot.hasDriver, isTrue);
      expect(snapshot.driverName, 'Tài Xế');
      expect(snapshot.driverLocation!.latitude, closeTo(10.7605, 1e-9));
      expect(snapshot.hospital!.assignedRoom, 'P2');
      expect(snapshot.isCompleted, isFalse);
    });

    test('ca vừa gửi chưa có tài xế', () {
      final snapshot = CaseSnapshot.fromJson(_json(
          '{"id":9,"status":"PENDING","patientLat":1,"patientLng":2,"driver":null,'
          '"driverLocation":null,"hospital":null,"hasRated":false}'));

      expect(snapshot.step, CaseStep.sent);
      expect(snapshot.hasDriver, isFalse);
      expect(snapshot.driverLocation, isNull);
    });

    test('mọi trạng thái chờ đều thuộc bước "đã gửi"', () {
      for (final status in ['PENDING', 'DISPATCHING', 'OPEN', 'ASSIGNED']) {
        expect(CaseSnapshot.stepFromStatus(status), CaseStep.sent, reason: status);
      }
      expect(CaseSnapshot.stepFromStatus('ACCEPTED'), CaseStep.accepted);
      expect(CaseSnapshot.stepFromStatus('PICKED_UP'), CaseStep.pickedUp);
      expect(CaseSnapshot.stepFromStatus('COMPLETED'), CaseStep.completed);
    });
  });

  group('PatientRegistration', () {
    test('ngày sinh gửi đi không lệch múi giờ', () {
      final form = PatientRegistration(
        fullName: 'A',
        phoneNumber: '0900000000',
        birthDate: DateTime(1995, 4, 2, 23, 30),
        gender: 'Nam',
        permanentAddress: 'x',
        emergencyContactName: 'B',
        emergencyContactPhone: '0900000001',
      );

      expect(form.toJson()['BirthDate'], '1995-04-02T00:00:00');
    });
  });

  group('AppSession', () {
    test('lưu rồi đọc lại giữ nguyên dữ liệu', () {
      const session = AppSession(
        role: UserRole.patient,
        token: 'abc',
        loginName: '0900000000',
        displayName: 'Nguyễn A',
        patientProfileId: 12,
      );

      final restored = AppSession.fromJson(jsonDecode(jsonEncode(session.toJson())));

      expect(restored!.role, UserRole.patient);
      expect(restored.token, 'abc');
      expect(restored.displayName, 'Nguyễn A');
      expect(restored.patientProfileId, 12);
    });

    test('dữ liệu lưu bị hỏng thì coi như chưa đăng nhập', () {
      expect(AppSession.fromJson(null), isNull);
      expect(AppSession.fromJson({'role': 'driver'}), isNull);
      expect(AppSession.fromJson({'role': 'admin', 'token': 'x'}), isNull);
    });
  });
}
