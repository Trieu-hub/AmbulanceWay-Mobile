import '../core/api_client.dart';
import '../core/json_reader.dart';
import '../models/driver_models.dart';
import '../models/hospital.dart';

/// Các API phía tài xế.
class DriverApi {
  DriverApi(this._api);

  final ApiClient _api;

  static const String statusPickedUp = 'PICKED_UP';
  static const String statusCompleted = 'COMPLETED';

  Future<DriverProfile> me() async =>
      DriverProfile.fromJson(JsonReader.tryFrom(await _api.get('/api/mobile/driver/me')) ??
          JsonReader(null));

  /// ONLINE khi vào ca, OFFLINE khi hết ca: máy chủ chỉ điều phối SOS cho tài xế ONLINE.
  Future<void> setOnline(bool online) => _api.post('/api/mobile/driver/status',
      body: {'Status': online ? 'ONLINE' : 'OFFLINE'});

  /// Thời điểm bắt đầu ca trực đang mở, null nếu chưa vào ca.
  Future<DateTime?> currentDutyStart() async {
    final data = JsonReader.tryFrom(await _api.get('/api/duty/current'));
    if (data == null || !data.boolean('onDuty')) return null;
    return data.object('duty')?.serverTime('startTime') ?? DateTime.now();
  }

  Future<void> startDuty(DriverProfile profile) => _api.post('/api/duty/start', body: {
        'HospitalName': profile.station,
        'StaffName': profile.driverName,
        // Cột VehicleNo của bảng DutySessions giới hạn 20 ký tự.
        'VehicleNo': profile.vehicle.length > 20
            ? profile.vehicle.substring(0, 20)
            : profile.vehicle,
      });

  Future<void> endDuty() => _api.post('/api/duty/end');

  Future<List<PendingCase>> pendingCases() async =>
      JsonReader.listFrom(await _api.get('/api/mobile/driver/cases/pending'))
          .map(PendingCase.fromApi)
          .toList();

  /// Ca tài xế đang làm dở (để khôi phục khi mở lại app), null nếu không có.
  Future<Mission?> activeMission() async {
    final data = JsonReader.tryFrom(await _api.get('/api/mobile/driver/cases/active'));
    final caseJson = data?.object('case');
    if (data == null || !data.boolean('hasCase') || caseJson == null) return null;
    return Mission.fromApi(caseJson);
  }

  /// POST /api/Sos/{id}/accept - máy chủ khóa bản ghi nên chỉ một tài xế nhận được.
  Future<void> acceptCase(int caseId, String username) =>
      _api.post('/api/Sos/$caseId/accept', body: {'DriverUsername': username});

  /// PUT /api/Sos/{id}/status
  Future<void> updateCaseStatus(
    int caseId,
    String status, {
    double? distanceKm,
    int? durationMinutes,
  }) =>
      _api.put('/api/Sos/$caseId/status', body: {
        'Status': status,
        'DistanceKm': ?distanceKm,
        'DurationMinutes': ?durationMinutes,
      });

  /// Tài xế chốt bệnh viện đích sau khi đón bệnh nhân.
  Future<Hospital> setDestination(int caseId, int hospitalId) async {
    final data = JsonReader.tryFrom(await _api.post(
        '/api/mobile/driver/cases/$caseId/destination',
        body: {'HospitalId': hospitalId}));
    final hospital = data?.object('hospital');
    if (hospital == null) throw ApiException('Máy chủ không trả về thông tin bệnh viện.');
    return Hospital.fromJson(hospital);
  }

  /// Tất cả bệnh viện đang hoạt động (GET /api/Hospitals).
  Future<List<Hospital>> hospitals() async =>
      JsonReader.listFrom(await _api.get('/api/Hospitals')).map(Hospital.fromJson).toList();

  Future<TripPage> trips({int page = 1, int pageSize = 50}) async =>
      TripPage.fromJson(JsonReader.tryFrom(await _api.get('/api/mobile/driver/trips',
              query: {'page': '$page', 'pageSize': '$pageSize'})) ??
          JsonReader(null));
}
