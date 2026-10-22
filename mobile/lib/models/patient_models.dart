import 'package:latlong2/latlong.dart';

import '../core/json_reader.dart';
import 'hospital.dart';

/// Hồ sơ y tế của bệnh nhân (GET /api/mobile/patient/me).
class PatientProfile {
  const PatientProfile({
    required this.id,
    required this.fullName,
    required this.phoneNumber,
    this.birthDate,
    this.gender,
    this.permanentAddress,
    this.medicalHistory,
    this.drugAllergies,
    this.emergencyContactName,
    this.emergencyContactPhone,
  });

  final int id;
  final String fullName;
  final String phoneNumber;
  final DateTime? birthDate;
  final String? gender;
  final String? permanentAddress;
  final String? medicalHistory;
  final String? drugAllergies;
  final String? emergencyContactName;
  final String? emergencyContactPhone;

  factory PatientProfile.fromJson(JsonReader json) => PatientProfile(
        id: json.integer('id'),
        fullName: json.string('fullName'),
        phoneNumber: json.string('phoneNumber'),
        birthDate: json.date('birthDate'),
        gender: json.stringOrNull('gender'),
        permanentAddress: json.stringOrNull('permanentAddress'),
        medicalHistory: json.stringOrNull('medicalHistory'),
        drugAllergies: json.stringOrNull('drugAllergies'),
        emergencyContactName: json.stringOrNull('emergencyContactName'),
        emergencyContactPhone: json.stringOrNull('emergencyContactPhone'),
      );
}

/// Dữ liệu form đăng ký hồ sơ (POST /api/patientauth/register).
class PatientRegistration {
  const PatientRegistration({
    required this.fullName,
    required this.phoneNumber,
    required this.birthDate,
    required this.gender,
    required this.permanentAddress,
    required this.emergencyContactName,
    required this.emergencyContactPhone,
    this.medicalHistory,
    this.drugAllergies,
  });

  final String fullName;
  final String phoneNumber;
  final DateTime birthDate;
  final String gender;
  final String permanentAddress;
  final String emergencyContactName;
  final String emergencyContactPhone;
  final String? medicalHistory;
  final String? drugAllergies;

  Map<String, dynamic> toJson() => {
        'FullName': fullName,
        'PhoneNumber': phoneNumber,
        // Chỉ gửi phần ngày để không lệch múi giờ.
        'BirthDate':
            '${birthDate.year.toString().padLeft(4, '0')}-${birthDate.month.toString().padLeft(2, '0')}-${birthDate.day.toString().padLeft(2, '0')}T00:00:00',
        'Gender': gender,
        'PermanentAddress': permanentAddress,
        'MedicalHistory': medicalHistory,
        'DrugAllergies': drugAllergies,
        'EmergencyContactName': emergencyContactName,
        'EmergencyContactPhone': emergencyContactPhone,
      };
}

/// Kết quả xin mã OTP. Backend V1 chưa gửi SMS nên trả luôn mã về để thử nghiệm.
class OtpTicket {
  const OtpTicket({required this.phoneNumber, this.devOtp, this.expiresInSeconds = 300});

  final String phoneNumber;
  final String? devOtp;
  final int expiresInSeconds;
}

/// Các bước hiển thị trên màn hình theo dõi của bệnh nhân.
enum CaseStep { sent, accepted, pickedUp, delivering, completed }

/// Ảnh chụp trạng thái một ca cấp cứu phía bệnh nhân
/// (GET /api/mobile/patient/cases/{id}).
class CaseSnapshot {
  const CaseSnapshot({
    required this.id,
    required this.status,
    required this.emergencyType,
    required this.description,
    required this.patientAddress,
    required this.patientLocation,
    this.createdAt,
    this.driverName,
    this.driverPhone,
    this.vehicle,
    this.driverLocation,
    this.hospital,
    this.hasRated = false,
  });

  final int id;
  final String status;
  final String emergencyType;
  final String description;
  final String patientAddress;
  final LatLng patientLocation;
  final DateTime? createdAt;
  final String? driverName;
  final String? driverPhone;
  final String? vehicle;
  final LatLng? driverLocation;
  final Hospital? hospital;
  final bool hasRated;

  bool get hasDriver => driverName != null;
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED' || status == 'REJECTED';

  CaseStep get step => stepFromStatus(status);

  static CaseStep stepFromStatus(String status) {
    switch (status) {
      case 'ACCEPTED':
        return CaseStep.accepted;
      case 'PICKED_UP':
        return CaseStep.pickedUp;
      case 'DELIVERING':
        return CaseStep.delivering;
      case 'COMPLETED':
        return CaseStep.completed;
      default:
        // PENDING, DISPATCHING, OPEN, ASSIGNED: đã gửi, chưa có tài xế xác nhận.
        return CaseStep.sent;
    }
  }

  factory CaseSnapshot.fromJson(JsonReader json) {
    final driver = json.object('driver');
    final driverLocation = json.object('driverLocation');
    final hospital = json.object('hospital');
    return CaseSnapshot(
      id: json.integer('id'),
      status: json.string('status', 'PENDING'),
      emergencyType: json.string('emergencyType'),
      description: json.string('description'),
      patientAddress: json.string('patientAddress'),
      patientLocation: LatLng(json.number('patientLat'), json.number('patientLng')),
      createdAt: json.serverTime('createdAt'),
      driverName: driver?.stringOrNull('name'),
      driverPhone: driver?.stringOrNull('phone'),
      vehicle: driver?.stringOrNull('vehicle'),
      driverLocation: driverLocation == null
          ? null
          : LatLng(driverLocation.number('lat'), driverLocation.number('lng')),
      hospital: hospital == null ? null : Hospital.fromJson(hospital),
      hasRated: json.boolean('hasRated'),
    );
  }

  CaseSnapshot copyWith({
    String? status,
    String? driverName,
    String? driverPhone,
    String? vehicle,
    LatLng? driverLocation,
    Hospital? hospital,
    bool? hasRated,
  }) =>
      CaseSnapshot(
        id: id,
        status: status ?? this.status,
        emergencyType: emergencyType,
        description: description,
        patientAddress: patientAddress,
        patientLocation: patientLocation,
        createdAt: createdAt,
        driverName: driverName ?? this.driverName,
        driverPhone: driverPhone ?? this.driverPhone,
        vehicle: vehicle ?? this.vehicle,
        driverLocation: driverLocation ?? this.driverLocation,
        hospital: hospital ?? this.hospital,
        hasRated: hasRated ?? this.hasRated,
      );
}

/// Điểm đánh giá của bệnh nhân sau chuyến (mỗi tiêu chí 1-5).
class RatingForm {
  const RatingForm({
    this.overall = 5,
    this.responseTime = 5,
    this.driverAttitude = 5,
    this.vehicleCondition = 5,
    this.situationHandling = 5,
    this.comment,
  });

  final int overall;
  final int responseTime;
  final int driverAttitude;
  final int vehicleCondition;
  final int situationHandling;
  final String? comment;

  Map<String, dynamic> toJson() => {
        'OverallRating': overall,
        'ResponseTimeRating': responseTime,
        'DriverAttitudeRating': driverAttitude,
        'VehicleConditionRating': vehicleCondition,
        'SituationHandlingRating': situationHandling,
        'Comment': comment,
      };
}
