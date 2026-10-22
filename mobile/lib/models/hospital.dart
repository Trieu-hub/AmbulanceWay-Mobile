import 'package:latlong2/latlong.dart';

import '../core/json_reader.dart';

/// Bệnh viện tiếp nhận.
class Hospital {
  const Hospital({
    required this.id,
    required this.name,
    required this.location,
    this.address = '',
    this.phone,
    this.availableBeds,
    this.receptionStatus,
    this.assignedRoom,
    this.notified = false,
  });

  final int id;
  final String name;
  final LatLng location;
  final String address;
  final String? phone;
  final int? availableBeds;

  /// OPEN / FULL / CLOSED
  final String? receptionStatus;

  /// Phòng/khu vực bệnh viện chỉ định khi xác nhận tiếp nhận.
  final String? assignedRoom;

  /// Máy chủ đã phát tín hiệu "có bệnh nhân đang đến" cho bệnh viện này.
  final bool notified;

  bool get isOpen => receptionStatus == null || receptionStatus == 'OPEN';

  /// Dùng cho GET /api/Hospitals (PascalCase) và các DTO của /api/mobile (camelCase).
  factory Hospital.fromJson(JsonReader json) => Hospital(
        id: json.integer('id'),
        name: json.string('name', 'Bệnh viện'),
        location: LatLng(json.number('lat'), json.number('lng')),
        address: json.string('address'),
        phone: json.stringOrNull('phone'),
        availableBeds: json.intOrNull('availableEmergencyBeds'),
        receptionStatus: json.stringOrNull('receptionStatus'),
        assignedRoom: json.stringOrNull('assignedRoom'),
      );

  /// Payload của sự kiện SignalR "HospitalConfirmed".
  factory Hospital.fromConfirmation(JsonReader json) => Hospital(
        id: json.integer('hospitalId'),
        name: json.string('hospitalName', 'Bệnh viện'),
        location: LatLng(json.number('hospitalLat'), json.number('hospitalLng')),
        address: json.string('hospitalAddress'),
        assignedRoom: json.stringOrNull('assignedRoom'),
      );

  Hospital copyWith({String? assignedRoom, bool? notified}) => Hospital(
        id: id,
        name: name,
        location: location,
        address: address,
        phone: phone,
        availableBeds: availableBeds,
        receptionStatus: receptionStatus,
        assignedRoom: assignedRoom ?? this.assignedRoom,
        notified: notified ?? this.notified,
      );
}
