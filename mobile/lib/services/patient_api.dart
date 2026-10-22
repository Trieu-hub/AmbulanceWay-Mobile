import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/json_reader.dart';
import '../models/patient_models.dart';

/// Các API phía bệnh nhân.
class PatientApi {
  PatientApi(this._api);

  final ApiClient _api;

  Future<PatientProfile> me() async => PatientProfile.fromJson(
      JsonReader.tryFrom(await _api.get('/api/mobile/patient/me')) ?? JsonReader(null));

  /// Ca đang diễn ra hoặc vừa xong mà chưa đánh giá; null nếu không có.
  Future<CaseSnapshot?> activeCase() async {
    final data = JsonReader.tryFrom(await _api.get('/api/mobile/patient/cases/active'));
    final caseJson = data?.object('case');
    if (data == null || !data.boolean('hasCase') || caseJson == null) return null;
    return CaseSnapshot.fromJson(caseJson);
  }

  Future<CaseSnapshot> caseById(int caseId) async {
    final data = JsonReader.tryFrom(await _api.get('/api/mobile/patient/cases/$caseId'));
    if (data == null) throw ApiException('Không đọc được trạng thái ca cấp cứu.');
    return CaseSnapshot.fromJson(data);
  }

  /// POST /api/Sos - trả về mã ca cấp cứu vừa tạo.
  Future<int> sendSos({
    required int profileId,
    required String emergencyType,
    required String description,
    required String address,
    required LatLng location,
  }) async {
    final data = JsonReader.tryFrom(await _api.post('/api/Sos', body: {
      'EmergencyType': emergencyType,
      'Description': description,
      'PatientProfileId': profileId,
      'PatientLat': location.latitude,
      'PatientLng': location.longitude,
      'PatientAddress': address,
    }));
    final caseId = data?.intOrNull('caseId');
    if (caseId == null || caseId <= 0) {
      throw ApiException('Máy chủ không trả về mã ca cấp cứu.');
    }
    return caseId;
  }

  /// Hủy yêu cầu SOS khi xe chưa đón bệnh nhân.
  Future<void> cancelCase(int caseId, {String? reason}) =>
      _api.post('/api/mobile/patient/cases/$caseId/cancel', body: {'Reason': reason});

  /// Sửa hồ sơ y tế (số điện thoại không đổi được). Trả về hồ sơ đã lưu.
  Future<PatientProfile> updateProfile(PatientRegistration form) async {
    final body = form.toJson()..remove('PhoneNumber');
    return PatientProfile.fromJson(
        JsonReader.tryFrom(await _api.put('/api/mobile/patient/me', body: body)) ?? JsonReader(null));
  }

  Future<void> submitRating(int caseId, RatingForm form) =>
      _api.post('/api/mobile/patient/cases/$caseId/rating', body: form.toJson());
}
