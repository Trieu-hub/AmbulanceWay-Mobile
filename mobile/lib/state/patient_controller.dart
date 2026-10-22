import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/json_reader.dart';
import '../models/hospital.dart';
import '../models/patient_models.dart';
import '../services/hub_client.dart';
import '../services/notification_service.dart';
import '../services/patient_api.dart';

/// Thông báo một lần cho màn hình theo dõi ("Đã có xe nhận ca"...).
class PatientNotice {
  const PatientNotice(this.message, {this.isError = false});
  final String message;
  final bool isError;
}

/// Nghiệp vụ phía bệnh nhân: gửi SOS, theo dõi ca realtime và đánh giá.
/// Tương ứng với trang /Patient/Sos của bản web.
class PatientController extends ChangeNotifier {
  PatientController({
    required ApiClient api,
    required this.profileId,
    this.skippedRatingCaseId,
    HubClient Function(String baseUrl)? hubFactory,
    this.notifier = const NoopNotifier(),
  })  : _api = PatientApi(api),
        _baseUrl = api.baseUrl,
        _hubFactory = hubFactory ?? HubClient.new;

  final PatientApi _api;
  final String _baseUrl;

  /// Test thay bằng hub giả để tự phát sự kiện realtime.
  final HubClient Function(String baseUrl) _hubFactory;
  final int profileId;

  /// Thông báo hệ thống khi app chạy nền (tài xế nhận ca, xe đã đón...).
  final AppNotifier notifier;

  /// Ca đã bấm "Bỏ qua" đánh giá ở lần dùng trước: không mở lại màn hình theo dõi cho ca này.
  final int? skippedRatingCaseId;

  final StreamController<PatientNotice> _notices = StreamController.broadcast();

  HubClient? _hub;
  Timer? _pollTimer;
  bool _disposed = false;
  bool _refreshing = false;

  // ----- Trạng thái cho giao diện -----

  Stream<PatientNotice> get notices => _notices.stream;

  PatientProfile? profile;
  bool loading = true;
  String? loadError;

  /// Ca đang theo dõi; null nghĩa là đang ở màn hình gửi SOS.
  CaseSnapshot? activeCase;

  /// ETA do tài xế gửi (tính từ lộ trình thực tế).
  int? etaMinutes;
  double? etaKm;

  HubStatus hubStatus = HubStatus.disconnected;
  bool sending = false;

  // ----- Khởi động -----

  Future<void> init() async {
    loading = true;
    loadError = null;
    _notify();
    try {
      profile = await _api.me();
      final current = await _api.activeCase();
      if (current != null && !(current.isCompleted && current.id == skippedRatingCaseId)) {
        _beginTracking(current);
      }
    } on ApiException catch (error) {
      loadError = error.message;
    } finally {
      loading = false;
      _notify();
    }
  }

  // ----- Gửi SOS -----

  /// Trả về câu báo lỗi, hoặc null nếu đã gửi và chuyển sang theo dõi.
  Future<String?> sendSos({
    required String emergencyType,
    required String description,
    required String address,
    required LatLng location,
  }) async {
    if (sending) return null;
    sending = true;
    _notify();
    // Để báo "tài xế đã nhận ca", "xe đã đón"... khi người dùng chuyển sang app khác trong lúc chờ.
    unawaited(notifier.requestPermission());
    try {
      final caseId = await _api.sendSos(
        profileId: profileId,
        emergencyType: emergencyType,
        description: description,
        address: address,
        location: location,
      );
      // Hiện màn hình theo dõi ngay, không chờ thêm một lượt gọi API.
      _beginTracking(CaseSnapshot(
        id: caseId,
        status: 'PENDING',
        emergencyType: emergencyType,
        description: description,
        patientAddress: address,
        patientLocation: location,
        createdAt: DateTime.now(),
      ));
      return null;
    } on ApiException catch (error) {
      return error.message;
    } finally {
      sending = false;
      _notify();
    }
  }

  // ----- Theo dõi ca -----

  void _beginTracking(CaseSnapshot snapshot) {
    activeCase = snapshot;
    etaMinutes = null;
    etaKm = null;
    if (snapshot.isCompleted || snapshot.isCancelled) return;

    final hub = _hubFactory(_baseUrl);
    hub.on('CaseAccepted', _onCaseAccepted);
    hub.on('EtaUpdated', _onEtaUpdated);
    hub.on('DriverLocationUpdate', _onDriverLocation);
    hub.on('CaseStatusUpdated', _onStatusUpdated);
    hub.on('HospitalConfirmed', _onHospitalConfirmed);
    hub.status.addListener(() {
      hubStatus = hub.status.value;
      _notify();
    });
    hub.onConnected = () async {
      final caseId = activeCase?.id;
      if (caseId == null) return;
      // Vào nhóm Case_{id} để nhận cập nhật của riêng ca này.
      await hub.invoke('JoinCase', [caseId]);
      // Sự kiện phát lúc chưa vào nhóm (hoặc lúc rớt mạng) sẽ không được gửi lại.
      await refresh();
    };
    _hub = hub;
    unawaited(hub.start());

    // Dự phòng khi SignalR bị chặn hoặc lỡ sự kiện.
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) => refresh());
  }

  void _stopTracking() {
    _pollTimer?.cancel();
    _pollTimer = null;
    final hub = _hub;
    _hub = null;
    hub?.dispose();
    hubStatus = HubStatus.disconnected;
  }

  /// Đọc lại trạng thái ca từ máy chủ.
  Future<void> refresh() async {
    final current = activeCase;
    if (current == null || _refreshing) return;
    _refreshing = true;
    try {
      final fresh = await _api.caseById(current.id);
      if (_disposed || activeCase?.id != fresh.id) return;
      _apply(fresh.copyWith(
        // Máy chủ chỉ nhớ vị trí xe trong bộ nhớ tạm; nếu không có thì giữ vị trí realtime gần nhất.
        driverLocation: fresh.driverLocation ?? activeCase?.driverLocation,
      ));
    } on ApiException {
      // Lượt đọc định kỳ sau sẽ thử lại.
    } finally {
      _refreshing = false;
    }
  }

  void _apply(CaseSnapshot next) {
    final previous = activeCase;
    activeCase = next;
    if (previous != null && previous.status != next.status) {
      _announce(previous, next);
      if (next.status == 'PICKED_UP') {
        // ETA cũ là thời gian xe tới chỗ bệnh nhân, không còn đúng.
        etaMinutes = null;
        etaKm = null;
      }
    }
    if (next.isCompleted || next.isCancelled) _stopTracking();
    _notify();
  }

  void _announce(CaseSnapshot previous, CaseSnapshot next) {
    final PatientNotice? notice = switch (next.status) {
      'ACCEPTED' => PatientNotice(
          'Tài xế ${next.driverName ?? ''} đã nhận ca và đang tới chỗ bạn.'.replaceAll('  ', ' ')),
      'PICKED_UP' => const PatientNotice('Xe cấp cứu đã đón bệnh nhân.'),
      'DELIVERING' => PatientNotice(next.hospital?.name == null
          ? 'Xe đang đưa bệnh nhân về bệnh viện.'
          : 'Xe đang đưa bệnh nhân về ${next.hospital!.name}.'),
      'COMPLETED' => const PatientNotice('Ca cấp cứu đã hoàn thành.'),
      'CANCELLED' || 'REJECTED' => const PatientNotice('Ca cấp cứu đã bị hủy.', isError: true),
      _ => null,
    };
    if (notice == null) return;
    _emit(notice);
    unawaited(notifier.info(next.id, 'Ca cấp cứu #${next.id}', notice.message));
  }

  bool _isThisCase(JsonReader json) => json.integer('caseId') == activeCase?.id;

  void _onCaseAccepted(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    final current = activeCase;
    if (json == null || current == null || !_isThisCase(json)) return;
    _apply(current.copyWith(
      status: current.step == CaseStep.sent ? 'ACCEPTED' : current.status,
      driverName: json.stringOrNull('driverName'),
      vehicle: json.stringOrNull('vehicle'),
      driverPhone: json.stringOrNull('phone'),
    ));
  }

  void _onEtaUpdated(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    if (json == null || !_isThisCase(json)) return;
    etaMinutes = json.intOrNull('durationMinutes');
    etaKm = json.doubleOrNull('distanceKm');
    _notify();
  }

  void _onDriverLocation(Object? payload) {
    // Sự kiện chỉ phát trong nhóm Case_{id} nên không kèm mã ca.
    final json = JsonReader.tryFrom(payload);
    final current = activeCase;
    final lat = json?.doubleOrNull('lat');
    final lng = json?.doubleOrNull('lng');
    if (current == null || lat == null || lng == null) return;
    activeCase = current.copyWith(driverLocation: LatLng(lat, lng));
    _notify();
  }

  void _onStatusUpdated(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    final current = activeCase;
    final status = json?.stringOrNull('status');
    if (json == null || current == null || status == null || !_isThisCase(json)) return;
    _apply(current.copyWith(status: status));
  }

  void _onHospitalConfirmed(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    final current = activeCase;
    if (json == null || current == null) return;
    final hospital = Hospital.fromConfirmation(json);
    final alreadyDelivering =
        current.step == CaseStep.delivering || current.step == CaseStep.completed;
    _apply(current.copyWith(
      hospital: hospital,
      status: alreadyDelivering ? current.status : 'DELIVERING',
    ));
  }

  // ----- Hủy yêu cầu -----

  /// Chỉ hủy được khi xe chưa đón bệnh nhân (máy chủ cũng kiểm tra lại).
  bool get canCancel {
    final step = activeCase?.step;
    return step == CaseStep.sent || step == CaseStep.accepted;
  }

  bool cancelling = false;

  /// Trả về câu báo lỗi, hoặc null nếu đã hủy và quay về màn hình gửi SOS.
  Future<String?> cancelCase({String? reason}) async {
    final current = activeCase;
    if (current == null || cancelling) return null;
    cancelling = true;
    _notify();
    try {
      await _api.cancelCase(current.id, reason: reason);
      closeCase();
      _emit(PatientNotice('Đã hủy yêu cầu cấp cứu #${current.id}.'));
      return null;
    } on ApiException catch (error) {
      // Xe có thể vừa đón bệnh nhân: đọc lại trạng thái để giao diện đúng với máy chủ.
      unawaited(refresh());
      return error.message;
    } finally {
      cancelling = false;
      _notify();
    }
  }

  // ----- Hồ sơ -----

  /// Trả về câu báo lỗi, hoặc null nếu đã lưu.
  Future<String?> updateProfile(PatientRegistration form) async {
    try {
      profile = await _api.updateProfile(form);
      _notify();
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  // ----- Đánh giá và kết thúc -----

  Future<String?> submitRating(RatingForm form) async {
    final current = activeCase;
    if (current == null) return null;
    try {
      await _api.submitRating(current.id, form);
      closeCase();
      return null;
    } on ApiException catch (error) {
      return error.message;
    }
  }

  /// Rời màn hình theo dõi, quay về màn hình gửi SOS.
  void closeCase() {
    _stopTracking();
    activeCase = null;
    etaMinutes = null;
    etaKm = null;
    _notify();
  }

  // ----- Tiện ích -----

  void _emit(PatientNotice notice) {
    if (!_notices.isClosed) _notices.add(notice);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _hub?.dispose();
    unawaited(_notices.close());
    super.dispose();
  }
}
