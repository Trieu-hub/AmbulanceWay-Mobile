import 'package:latlong2/latlong.dart';

import '../core/json_reader.dart';
import 'hospital.dart';

/// Hồ sơ tài xế (GET /api/mobile/driver/me).
class DriverProfile {
  const DriverProfile({
    required this.username,
    required this.driverName,
    required this.vehicle,
    required this.phone,
    required this.licenseNo,
    required this.station,
    required this.stationLocation,
    required this.status,
  });

  final String username;
  final String driverName;
  final String vehicle;
  final String phone;
  final String licenseNo;
  final String station;
  final LatLng stationLocation;
  final String status;

  factory DriverProfile.fromJson(JsonReader json) => DriverProfile(
        username: json.string('username'),
        driverName: json.string('driverName'),
        vehicle: json.string('vehicle', 'N/A'),
        phone: json.string('phone', 'N/A'),
        licenseNo: json.string('licenseNo', 'N/A'),
        station: json.string('station', 'N/A'),
        stationLocation:
            LatLng(json.number('stationLat'), json.number('stationLng')),
        status: json.string('status', 'OFFLINE'),
      );
}

/// Ca cấp cứu đang chờ tài xế nhận.
class PendingCase {
  const PendingCase({
    required this.caseId,
    required this.address,
    required this.summary,
    required this.location,
    this.etaMinutes,
    this.createdAt,
    this.assignedToMe = false,
  });

  final int caseId;
  final String address;

  /// "Loại khẩn cấp: mô tả"
  final String summary;
  final LatLng location;
  final int? etaMinutes;
  final DateTime? createdAt;

  /// Admin đã chỉ định ca này cho tài xế đang đăng nhập.
  final bool assignedToMe;

  /// Payload của sự kiện SignalR "ReceiveNewTrip".
  factory PendingCase.fromRealtime(JsonReader json) => PendingCase(
        caseId: json.integer('caseId'),
        address: json.string('address', 'Không rõ địa chỉ'),
        summary: json.string('hospital', 'Ca cấp cứu'),
        location: LatLng(json.number('lat'), json.number('lng')),
        etaMinutes: json.intOrNull('etaMinutes'),
        createdAt: DateTime.now(),
      );

  /// Phần tử của GET /api/mobile/driver/cases/pending.
  factory PendingCase.fromApi(JsonReader json) => PendingCase(
        caseId: json.integer('caseId'),
        address: json.string('address', 'Không rõ địa chỉ'),
        summary: buildSummary(json.string('emergencyType'), json.string('description')),
        location: LatLng(json.number('lat'), json.number('lng')),
        createdAt: json.serverTime('createdAt'),
        assignedToMe: json.string('status') == 'ASSIGNED',
      );

  static String buildSummary(String type, String description) {
    if (type.isEmpty) return description.isEmpty ? 'Ca cấp cứu' : description;
    return description.isEmpty ? type : '$type: $description';
  }
}

/// Thông tin bệnh nhân mà tài xế đã nhận ca được xem.
class PatientInfo {
  const PatientInfo({
    required this.fullName,
    required this.phoneNumber,
    this.gender,
    this.birthDate,
    this.medicalHistory,
    this.drugAllergies,
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  final String fullName;
  final String phoneNumber;
  final String? gender;
  final DateTime? birthDate;
  final String? medicalHistory;
  final String? drugAllergies;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  int? get age {
    final born = birthDate;
    if (born == null) return null;
    final now = DateTime.now();
    var years = now.year - born.year;
    if (now.month < born.month || (now.month == born.month && now.day < born.day)) {
      years--;
    }
    return years < 0 ? null : years;
  }

  factory PatientInfo.fromJson(JsonReader json) => PatientInfo(
        fullName: json.string('fullName', 'Bệnh nhân'),
        phoneNumber: json.string('phoneNumber'),
        gender: json.stringOrNull('gender'),
        birthDate: json.date('birthDate'),
        medicalHistory: json.stringOrNull('medicalHistory'),
        drugAllergies: json.stringOrNull('drugAllergies'),
        emergencyContactName: json.stringOrNull('emergencyContactName'),
        emergencyContactPhone: json.stringOrNull('emergencyContactPhone'),
      );
}

/// Các chặng của một nhiệm vụ sau khi tài xế nhận ca.
enum MissionPhase {
  /// Đang chạy tới chỗ bệnh nhân (ca ở trạng thái ACCEPTED).
  toPatient,

  /// Đã đón bệnh nhân, chưa chốt bệnh viện (PICKED_UP).
  pickedUp,

  /// Đang chở bệnh nhân về bệnh viện (DELIVERING).
  toHospital,
}

/// Nhiệm vụ tài xế đang thực hiện.
class Mission {
  const Mission({
    required this.caseId,
    required this.address,
    required this.summary,
    required this.patientLocation,
    required this.phase,
    this.patient,
    this.hospital,
    this.acceptedAt,
  });

  final int caseId;
  final String address;
  final String summary;
  final LatLng patientLocation;
  final MissionPhase phase;
  final PatientInfo? patient;
  final Hospital? hospital;
  final DateTime? acceptedAt;

  factory Mission.fromPending(PendingCase pending) => Mission(
        caseId: pending.caseId,
        address: pending.address,
        summary: pending.summary,
        patientLocation: pending.location,
        phase: MissionPhase.toPatient,
        acceptedAt: DateTime.now(),
      );

  /// Trường "case" của GET /api/mobile/driver/cases/active.
  factory Mission.fromApi(JsonReader json) {
    final hospitalJson = json.object('hospital');
    final patientJson = json.object('patient');
    final hospital = hospitalJson == null ? null : Hospital.fromJson(hospitalJson);
    return Mission(
      caseId: json.integer('caseId'),
      address: json.string('address', 'Không rõ địa chỉ'),
      summary: PendingCase.buildSummary(
          json.string('emergencyType'), json.string('description')),
      patientLocation: LatLng(json.number('lat'), json.number('lng')),
      phase: phaseFromStatus(json.string('status'), hasHospital: hospital != null),
      patient: patientJson == null ? null : PatientInfo.fromJson(patientJson),
      hospital: hospital,
      acceptedAt: json.serverTime('acceptedAt'),
    );
  }

  static MissionPhase phaseFromStatus(String status, {required bool hasHospital}) {
    switch (status) {
      case 'PICKED_UP':
        return MissionPhase.pickedUp;
      case 'DELIVERING':
        // Ca cũ có thể ở DELIVERING mà chưa ghi bệnh viện: cho tài xế chọn lại.
        return hasHospital ? MissionPhase.toHospital : MissionPhase.pickedUp;
      default:
        return MissionPhase.toPatient;
    }
  }

  Mission copyWith({
    MissionPhase? phase,
    PatientInfo? patient,
    Hospital? hospital,
  }) =>
      Mission(
        caseId: caseId,
        address: address,
        summary: summary,
        patientLocation: patientLocation,
        phase: phase ?? this.phase,
        patient: patient ?? this.patient,
        hospital: hospital ?? this.hospital,
        acceptedAt: acceptedAt,
      );
}

/// Một dòng lịch sử chuyến (GET /api/mobile/driver/trips).
class TripRecord {
  const TripRecord({
    required this.id,
    required this.hospitalName,
    required this.patientAddress,
    required this.distanceKm,
    required this.durationMinutes,
    required this.status,
    this.createdAt,
    this.completedAt,
  });

  final int id;
  final String hospitalName;
  final String patientAddress;
  final double distanceKm;
  final int durationMinutes;
  final String status;
  final DateTime? createdAt;
  final DateTime? completedAt;

  factory TripRecord.fromJson(JsonReader json) => TripRecord(
        id: json.integer('id'),
        hospitalName: json.string('hospitalName', 'Bệnh viện'),
        patientAddress: json.string('patientAddress'),
        distanceKm: json.number('distanceKm'),
        durationMinutes: json.integer('durationMinutes'),
        status: json.string('tripStatus', 'COMPLETED'),
        createdAt: json.serverTime('createdAt'),
        completedAt: json.serverTime('completedAt'),
      );
}

/// Một trang lịch sử chuyến kèm số liệu tổng.
class TripPage {
  const TripPage({
    required this.trips,
    required this.total,
    required this.totalDistanceKm,
  });

  final List<TripRecord> trips;
  final int total;
  final double totalDistanceKm;

  factory TripPage.fromJson(JsonReader json) => TripPage(
        trips: json.objects('data').map(TripRecord.fromJson).toList(),
        total: json.integer('total'),
        totalDistanceKm: json.number('totalDistanceKm'),
      );
}
