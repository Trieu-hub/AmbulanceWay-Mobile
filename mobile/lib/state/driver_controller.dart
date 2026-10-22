import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/geo.dart';
import '../core/json_reader.dart';
import '../models/driver_models.dart';
import '../models/hospital.dart';
import '../models/route_plan.dart';
import '../services/driver_api.dart';
import '../services/hub_client.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../services/routing_service.dart';

/// Sự kiện một lần mà giao diện phải phản hồi bằng hộp thoại hoặc thông báo.
sealed class DriverEvent {
  const DriverEvent();
}

/// Có SOS mới và tài xế đang rảnh: hiện hộp thoại nhận ca có đếm ngược.
class IncomingSosEvent extends DriverEvent {
  const IncomingSosEvent(this.request);
  final PendingCase request;
}

/// Bệnh viện đã xác nhận tiếp nhận, lộ trình chuyển sang bệnh viện đó.
class HospitalAcceptedEvent extends DriverEvent {
  const HospitalAcceptedEvent(this.hospital);
  final Hospital hospital;
}

class DriverNoticeEvent extends DriverEvent {
  const DriverNoticeEvent(this.message, {this.isError = false});
  final String message;
  final bool isError;
}

/// Toàn bộ nghiệp vụ phía tài xế: ca trực, kết nối realtime, GPS, hàng chờ SOS
/// và nhiệm vụ đang thực hiện. Tương ứng với trang /Home/Map của bản web.
class DriverController extends ChangeNotifier {
  DriverController({
    required ApiClient api,
    RoutingService? routing,
    LocationService? location,
    HubClient Function(String baseUrl)? hubFactory,
    this.notifier = const NoopNotifier(),
  })  : _api = DriverApi(api),
        _baseUrl = api.baseUrl,
        _routing = routing ?? RoutingService(),
        _location = location ?? LocationService(),
        _hubFactory = hubFactory ?? HubClient.new;

  final DriverApi _api;
  final String _baseUrl;
  final RoutingService _routing;
  final LocationService _location;

  /// Thông báo hệ thống khi app chạy nền (ca SOS mới, bệnh nhân hủy ca...).
  final AppNotifier notifier;

  /// Test thay bằng hub giả để tự phát sự kiện realtime.
  final HubClient Function(String baseUrl) _hubFactory;

  final StreamController<DriverEvent> _events = StreamController.broadcast();

  HubClient? _hub;
  StreamSubscription<LatLng>? _gpsSubscription;
  Timer? _tickTimer;
  int _tickCount = 0;
  bool _disposed = false;
  bool _hubConnectedBefore = false;
  bool _startingLocation = false;

  int? _acceptingCaseId;
  Set<int> _notifiedHospitalIds = {};

  // Lộ trình đầu tiên của mỗi chặng, cộng lại để ghi quãng đường khi hoàn thành.
  RoutePlan? _legToPatient;
  RoutePlan? _legToHospital;
  LatLng? _routeOrigin;
  DateTime? _routePlannedAt;
  int _routeRequestId = 0;

  // Tăng mỗi khi nhiệm vụ đổi trên máy này, để kết quả đọc từ máy chủ đến trễ không ghi đè lên.
  int _missionEpoch = 0;

  // ----- Trạng thái cho giao diện -----

  Stream<DriverEvent> get events => _events.stream;

  DriverProfile? profile;
  bool loading = true;
  String? loadError;

  bool onDuty = false;
  DateTime? dutyStartedAt;

  /// Đang chờ máy chủ xử lý một thao tác (vào ca, nhận ca, đổi trạng thái...).
  bool busy = false;

  HubStatus hubStatus = HubStatus.disconnected;

  LatLng? gpsPosition;
  LocationIssue? locationIssue;

  /// Chế độ mô phỏng: vị trí xe do người dùng chấm trên bản đồ thay cho GPS (để demo trên máy tính).
  bool simulateLocation = false;
  LatLng? simulatedPosition;

  List<PendingCase> pending = const [];
  Mission? mission;
  RoutePlan? route;
  bool routeLoading = false;

  List<Hospital> hospitalOptions = const [];
  bool hospitalsLoading = false;

  /// Vị trí gửi lên máy chủ: GPS thật hoặc vị trí mô phỏng. null nếu chưa có.
  LatLng? get reportedPosition => simulateLocation ? simulatedPosition : gpsPosition;

  /// Vị trí vẽ xe trên bản đồ và làm điểm xuất phát; chưa có GPS thì dùng trạm của tài xế (giống bản web).
  LatLng get mapPosition =>
      reportedPosition ?? profile?.stationLocation ?? AppConfig.defaultCenter;

  bool get hasRealPosition => reportedPosition != null;

  // ----- Khởi động -----

  Future<void> init() async {
    loading = true;
    loadError = null;
    _notify();
    try {
      profile = await _api.me();
      final dutyStart = await _api.currentDutyStart();
      if (dutyStart != null) {
        // Ca trực còn mở từ lần trước (app bị tắt giữa chừng): tiếp tục ca đó.
        onDuty = true;
        dutyStartedAt = dutyStart;
        await _goOnline();
      }
    } on ApiException catch (error) {
      loadError = error.message;
    } finally {
      loading = false;
      _notify();
    }
  }

  // ----- Ca trực -----

  /// Trả về câu báo lỗi, hoặc null nếu thành công.
  Future<String?> startDuty() async {
    final me = profile;
    if (me == null || busy || onDuty) return null;
    // Cần quyền thông báo để báo ca mới khi tài xế tắt màn hình (Android 13+ phải hỏi).
    unawaited(notifier.requestPermission());
    busy = true;
    _notify();
    try {
      try {
        await _api.startDuty(me);
      } on ApiException catch (error) {
        // 400 "Already on active duty": ca cũ chưa đóng thì dùng tiếp, lỗi khác thì báo.
        if (error.statusCode != 400 || await _api.currentDutyStart() == null) rethrow;
      }
      onDuty = true;
      dutyStartedAt = await _api.currentDutyStart() ?? DateTime.now();
      await _goOnline();
      return null;
    } on ApiException catch (error) {
      return error.message;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<String?> endDuty() async {
    if (!onDuty || busy) return null;
    if (mission != null) {
      return 'Hãy hoàn thành nhiệm vụ đang thực hiện trước khi kết thúc ca.';
    }
    busy = true;
    _notify();
    try {
      try {
        await _api.endDuty();
      } on ApiException catch (error) {
        // 400 "No active duty found": ca đã được đóng ở nơi khác.
        if (error.statusCode != 400) rethrow;
      }
      await _api.setOnline(false);
      await _goOffline();
      onDuty = false;
      dutyStartedAt = null;
      pending = const [];
      return null;
    } on ApiException catch (error) {
      return error.message;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> _goOnline() async {
    _startHub();
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(AppConfig.locationPushInterval, (_) => _tick());
    unawaited(startLocation());
    try {
      await _api.setOnline(true);
      await refreshCases();
    } on ApiException catch (error) {
      _emit(DriverNoticeEvent(error.message, isError: true));
    }
  }

  Future<void> _goOffline() async {
    _tickTimer?.cancel();
    _tickTimer = null;
    await _gpsSubscription?.cancel();
    _gpsSubscription = null;
    final hub = _hub;
    _hub = null;
    hub?.dispose();
    hubStatus = HubStatus.disconnected;
    _hubConnectedBefore = false;
  }

  // ----- Realtime (SignalR) -----

  void _startHub() {
    if (_hub != null) return;
    final hub = _hubFactory(_baseUrl);
    hub.on('ReceiveNewTrip', _onNewTrip);
    hub.on('CaseAlreadyTaken', _onCaseTaken);
    hub.on('SuggestHospitals', _onSuggestHospitals);
    hub.on('HospitalConfirmed', _onHospitalConfirmed);
    hub.on('CaseCancelled', _onCaseCancelled);
    // Máy chủ còn phát sự kiện này cho nhóm Drivers; đăng ký để thư viện không ghi cảnh báo.
    hub.on('HospitalCapacityUpdated', (_) {});
    hub.status.addListener(() {
      hubStatus = hub.status.value;
      _notify();
    });
    hub.onConnected = () async {
      final me = profile;
      if (me == null) return;
      // Bắt buộc: máy chủ chỉ gửi SOS cho kết nối đã RegisterDriver.
      await hub.invoke('RegisterDriver', [me.username]);
      _pushLocation();
      if (_hubConnectedBefore) {
        // Vừa nối lại sau khi rớt mạng: có thể đã lỡ sự kiện nên đọc lại từ máy chủ.
        await _refreshQuietly();
      }
      _hubConnectedBefore = true;
    };
    _hub = hub;
    unawaited(hub.start());
  }

  void _onNewTrip(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    if (json == null) return;
    final request = PendingCase.fromRealtime(json);
    // CaseId = 0 là lệnh điều phối kiểu cũ (bảng AmbulanceTrips), không nhận được qua /api/Sos.
    if (request.caseId <= 0 || mission?.caseId == request.caseId) return;

    if (!pending.any((item) => item.caseId == request.caseId)) {
      pending = [request, ...pending];
      _notify();
    }
    if (mission == null) {
      _emit(IncomingSosEvent(request));
      unawaited(notifier.urgent(request.caseId, 'Ca cấp cứu mới #${request.caseId}',
          '${request.summary}\n${request.address}'));
    } else {
      _emit(DriverNoticeEvent('Có ca cấp cứu mới đang chờ: ${request.address}'));
    }
  }

  void _onCaseTaken(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    if (json == null) return;
    final caseId = json.integer('caseId');
    // Máy chủ phát cho cả nhóm Drivers, kể cả chính tài xế vừa nhận ca.
    if (caseId == mission?.caseId || caseId == _acceptingCaseId) return;
    if (!pending.any((item) => item.caseId == caseId)) return;

    pending = pending.where((item) => item.caseId != caseId).toList();
    _notify();
    _emit(DriverNoticeEvent(
        'Tài xế ${json.string('takenBy', 'khác')} đã nhận ca #$caseId trước bạn.'));
  }

  /// Bệnh nhân hủy yêu cầu SOS (trước khi xe đón).
  void _onCaseCancelled(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    if (json == null) return;
    final caseId = json.integer('caseId');
    final reason = json.stringOrNull('reason');
    final current = mission;
    if (current != null && current.caseId == caseId) {
      _clearMission();
      _notify();
      final message = 'Bệnh nhân đã hủy ca #$caseId${reason == null ? '' : ' ($reason)'}. Bạn có thể nhận ca khác.';
      _emit(DriverNoticeEvent(message, isError: true));
      unawaited(notifier.urgent(caseId, 'Ca #$caseId đã bị hủy', message));
      return;
    }
    if (!pending.any((item) => item.caseId == caseId)) return;
    pending = pending.where((item) => item.caseId != caseId).toList();
    _notify();
    _emit(DriverNoticeEvent('Ca #$caseId đã được bệnh nhân hủy.'));
  }

  void _onSuggestHospitals(Object? payload) {
    _notifiedHospitalIds =
        JsonReader.listFrom(payload).map((item) => item.integer('id')).toSet();
    hospitalOptions = [
      for (final hospital in hospitalOptions)
        hospital.copyWith(notified: _notifiedHospitalIds.contains(hospital.id)),
    ];
    _notify();
  }

  void _onHospitalConfirmed(Object? payload) {
    final json = JsonReader.tryFrom(payload);
    final current = mission;
    if (json == null || current == null || current.phase == MissionPhase.toPatient) return;

    final hospital = Hospital.fromConfirmation(json);
    if (json.string('status').toUpperCase() == 'REJECTED') {
      final reason = json.stringOrNull('rejectReason');
      _emit(DriverNoticeEvent(
          '${hospital.name} từ chối tiếp nhận${reason == null ? '' : ' ($reason)'}.',
          isError: true));
      return;
    }
    if (hospital.location.latitude == 0 && hospital.location.longitude == 0) return;

    mission = current.copyWith(phase: MissionPhase.toHospital, hospital: hospital);
    _missionEpoch++;
    _legToHospital = null;
    route = null;
    _notify();
    _emit(HospitalAcceptedEvent(hospital));
    unawaited(notifier.info(current.caseId, '${hospital.name} nhận bệnh nhân',
        hospital.assignedRoom == null ? 'Lộ trình đã chuyển về bệnh viện.' : 'Đưa bệnh nhân vào: ${hospital.assignedRoom}'));
    unawaited(_planRoute());
  }

  // ----- Vị trí -----

  /// Xin quyền và bắt đầu nghe GPS. Gọi lại được khi người dùng bấm "Thử lại".
  Future<void> startLocation() async {
    if (_startingLocation) return;
    _startingLocation = true;
    try {
      final issue = await _location.ensureReady();
      if (_disposed || !onDuty) return;
      locationIssue = issue;
      _notify();
      if (issue != null) return;

      await _gpsSubscription?.cancel();
      _gpsSubscription = _location.watch(keepAliveInBackground: true).listen(
        (position) {
          final first = gpsPosition == null;
          gpsPosition = position;
          // Có vị trí mới nghĩa là GPS đã hoạt động lại sau lần lỗi trước (nếu có).
          locationIssue = null;
          if (first) _pushLocation();
          _notify();
        },
        onError: (Object _) {
          // Lỗi tạm thời (mất tín hiệu): giữ vị trí gần nhất, _tick sẽ thử nghe lại.
          locationIssue = LocationIssue.unavailable;
          _notify();
        },
        onDone: () {
          // Có nền tảng đóng luồng vị trí khi người dùng tắt GPS giữa chừng.
          if (_disposed || !onDuty) return;
          locationIssue = LocationIssue.unavailable;
          _notify();
        },
      );
    } finally {
      _startingLocation = false;
    }
  }

  /// Lỗi vị trí có thể tự hết (mất tín hiệu, GPS vừa bật lại). Thiếu quyền thì không tự thử lại
  /// vì sẽ làm hộp thoại xin quyền hiện lặp đi lặp lại; người dùng bấm "Thử lại" khi đã cấp quyền.
  bool get _locationMayRecover =>
      locationIssue == LocationIssue.unavailable ||
      locationIssue == LocationIssue.serviceDisabled;

  void setSimulateLocation(bool enabled) {
    simulateLocation = enabled;
    if (enabled) {
      simulatedPosition ??= gpsPosition ?? profile?.stationLocation ?? AppConfig.defaultCenter;
    }
    _notify();
    _pushLocation();
  }

  /// Đặt vị trí xe khi đang ở chế độ mô phỏng (nhấn giữ trên bản đồ).
  void moveSimulatedPosition(LatLng point) {
    if (!simulateLocation) return;
    simulatedPosition = point;
    _notify();
    _pushLocation();
  }

  void _pushLocation() {
    final hub = _hub;
    final me = profile;
    final position = reportedPosition;
    if (hub == null || me == null || position == null || !hub.isConnected) return;

    // Admin thấy xe trên bản đồ; máy chủ dùng vị trí này để chọn tài xế trong bán kính 5 km.
    unawaited(hub.invoke(
        'SendLocationUpdate', [me.username, position.latitude, position.longitude]));

    final current = mission;
    if (current != null) {
      // Người nhà bệnh nhân theo dõi xe của ca này.
      unawaited(hub.invoke('SendDriverLocationToCase',
          [current.caseId, me.username, position.latitude, position.longitude]));
    }
  }

  void _tick() {
    _tickCount++;
    _pushLocation();

    // Xe đã đi xa điểm tính đường cũ thì tính lại để cập nhật quãng đường và ETA còn lại.
    final origin = _routeOrigin;
    final plannedAt = _routePlannedAt;
    if (mission != null && route != null && !routeLoading && origin != null && plannedAt != null) {
      final movedMeters = haversineKm(origin, mapPosition) * 1000;
      final age = DateTime.now().difference(plannedAt);
      if (movedMeters > 150 && age > const Duration(seconds: 20)) {
        unawaited(_planRoute());
      }
    }

    if (_tickCount % 6 != 0) return;

    // Mỗi 30 giây đọc lại hàng chờ phòng khi lỡ sự kiện realtime...
    if (!busy) unawaited(_refreshQuietly());
    // ...và thử nghe lại GPS nếu đang lỗi.
    if (!simulateLocation && _locationMayRecover) unawaited(startLocation());
  }

  // ----- Hàng chờ và nhiệm vụ -----

  /// Đọc lại từ máy chủ: ca đang làm dở và các ca đang chờ.
  Future<void> refreshCases() async {
    final epoch = _missionEpoch;
    final active = await _api.activeMission();
    final waiting = await _api.pendingCases();
    if (_disposed) return;

    // Nếu tài xế vừa thao tác (nhận ca, hoàn thành...) trong lúc chờ thì dữ liệu này đã cũ.
    if (epoch == _missionEpoch) _syncMission(active);

    pending = waiting.where((item) => item.caseId != mission?.caseId).toList();
    _notify();
  }

  void _syncMission(Mission? active) {
    final current = mission;
    if (active == null) {
      if (current != null) _clearMission();
      return;
    }

    if (current == null || current.caseId != active.caseId) {
      // Mở lại app giữa chừng, hoặc Admin vừa chuyển sang ca khác.
      _clearMission();
      mission = active;
    } else if (current.phase != active.phase) {
      // Cùng ca nhưng máy chủ đã sang chặng khác (ví dụ bệnh viện xác nhận lúc app mất kết nối).
      mission = active;
      route = null;
      routeLoading = false;
      _routeRequestId++;
      _missionEpoch++;
    } else {
      if (current.patient == null && active.patient != null) {
        mission = current.copyWith(patient: active.patient);
      }
      return;
    }

    if (active.phase == MissionPhase.pickedUp) {
      unawaited(loadHospitalOptions());
    } else {
      unawaited(_planRoute());
    }
  }

  Future<void> _refreshQuietly() async {
    try {
      await refreshCases();
    } on ApiException {
      // Lần đọc định kỳ tiếp theo sẽ thử lại.
    }
  }

  void _clearMission() {
    _missionEpoch++;
    mission = null;
    route = null;
    routeLoading = false;
    _routeRequestId++;
    _legToPatient = null;
    _legToHospital = null;
    _routeOrigin = null;
    _routePlannedAt = null;
    hospitalOptions = const [];
    _notifiedHospitalIds = {};
  }

  /// Nhận ca. Trả về câu báo lỗi, hoặc null nếu nhận thành công.
  Future<String?> acceptCase(PendingCase request) async {
    final me = profile;
    if (me == null || busy) return 'Đang xử lý thao tác trước, vui lòng thử lại.';
    if (mission != null) return 'Bạn đang thực hiện một ca khác.';

    busy = true;
    _acceptingCaseId = request.caseId;
    _notify();
    try {
      await _api.acceptCase(request.caseId, me.username);
      _clearMission();
      mission = Mission.fromPending(request);
      pending = pending.where((item) => item.caseId != request.caseId).toList();
      _notify();
      _pushLocation();
      unawaited(_refreshQuietly()); // lấy thông tin bệnh nhân của ca vừa nhận
      await _planRoute();
      return null;
    } on ApiException catch (error) {
      // Ca đã có người nhận hoặc đã kết thúc: bỏ khỏi hàng chờ.
      if (!error.isNetworkError) {
        pending = pending.where((item) => item.caseId != request.caseId).toList();
      }
      return error.message;
    } finally {
      busy = false;
      _acceptingCaseId = null;
      _notify();
    }
  }

  /// Bỏ qua một ca trong hàng chờ (chỉ ẩn trên máy này, tài xế khác vẫn thấy).
  void dismissPending(int caseId) {
    pending = pending.where((item) => item.caseId != caseId).toList();
    _notify();
  }

  Future<String?> markPickedUp() async {
    final current = mission;
    if (current == null || busy) return null;
    busy = true;
    _notify();
    try {
      // Máy chủ sẽ báo cho các bệnh viện trong bán kính 5 km và gửi lại sự kiện SuggestHospitals.
      await _api.updateCaseStatus(current.caseId, DriverApi.statusPickedUp);
      mission = current.copyWith(phase: MissionPhase.pickedUp);
      _missionEpoch++;
      route = null;
      _routeRequestId++;
      routeLoading = false;
      _notify();
      unawaited(loadHospitalOptions());
      return null;
    } on ApiException catch (error) {
      return await _missionError(error);
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Các bệnh viện đang nhận bệnh, gần vị trí hiện tại nhất.
  Future<void> loadHospitalOptions() async {
    hospitalsLoading = true;
    _notify();
    try {
      final origin = mapPosition;
      final open = (await _api.hospitals()).where((hospital) => hospital.isOpen).toList()
        ..sort((a, b) => haversineKm(origin, a.location)
            .compareTo(haversineKm(origin, b.location)));
      hospitalOptions = [
        for (final hospital in open.take(6))
          hospital.copyWith(notified: _notifiedHospitalIds.contains(hospital.id)),
      ];
    } on ApiException catch (error) {
      _emit(DriverNoticeEvent(error.message, isError: true));
    } finally {
      hospitalsLoading = false;
      _notify();
    }
  }

  /// Tài xế chốt bệnh viện đích và bắt đầu chặng về viện.
  Future<String?> chooseHospital(Hospital hospital) async {
    final current = mission;
    if (current == null || busy) return null;
    busy = true;
    _notify();
    try {
      final confirmed = await _api.setDestination(current.caseId, hospital.id);
      mission = current.copyWith(phase: MissionPhase.toHospital, hospital: confirmed);
      _missionEpoch++;
      _legToHospital = null;
      _notify();
      await _planRoute();
      return null;
    } on ApiException catch (error) {
      return await _missionError(error);
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<String?> completeMission() async {
    final current = mission;
    if (current == null || busy) return null;
    busy = true;
    _notify();
    try {
      final distanceKm =
          (_legToPatient?.distanceKm ?? 0) + (_legToHospital?.distanceKm ?? 0);
      final minutes =
          (_legToPatient?.durationMinutes ?? 0) + (_legToHospital?.durationMinutes ?? 0);
      // Không có số liệu lộ trình (ca khôi phục sau khi mở lại app) thì để máy chủ tự tính.
      await _api.updateCaseStatus(
        current.caseId,
        DriverApi.statusCompleted,
        distanceKm: distanceKm > 0 ? double.parse(distanceKm.toStringAsFixed(2)) : null,
        durationMinutes: minutes > 0 ? minutes : null,
      );
      _clearMission();
      _notify();
      unawaited(_refreshQuietly());
      return null;
    } on ApiException catch (error) {
      return await _missionError(error);
    } finally {
      busy = false;
      _notify();
    }
  }

  /// Máy chủ từ chối thao tác trên ca (ví dụ ca đã bị Admin xóa hay đã kết thúc):
  /// đồng bộ lại để giao diện không kẹt ở một nhiệm vụ không còn tồn tại.
  Future<String> _missionError(ApiException error) async {
    if (!error.isNetworkError) await _refreshQuietly();
    return error.message;
  }

  // ----- Lộ trình -----

  Future<void> _planRoute() async {
    final current = mission;
    if (current == null) return;

    final LatLng? target = switch (current.phase) {
      MissionPhase.toPatient => current.patientLocation,
      MissionPhase.toHospital => current.hospital?.location,
      MissionPhase.pickedUp => null,
    };
    if (target == null) return;

    final requestId = ++_routeRequestId;
    final origin = mapPosition;
    routeLoading = true;
    _notify();

    final plan = await _routing.route(origin, target);
    // Trong lúc chờ, nhiệm vụ có thể đã đổi chặng hoặc kết thúc: bỏ kết quả cũ.
    if (_disposed || requestId != _routeRequestId) return;

    route = plan;
    routeLoading = false;
    _routeOrigin = origin;
    _routePlannedAt = DateTime.now();
    if (current.phase == MissionPhase.toPatient) {
      _legToPatient ??= plan;
    } else {
      _legToHospital ??= plan;
    }
    _notify();

    // Người nhà bệnh nhân và Admin nhận ETA thực tế (sự kiện EtaUpdated).
    unawaited(_hub?.invoke('SendEtaUpdate', [
      current.caseId,
      double.parse(plan.distanceKm.toStringAsFixed(2)),
      plan.durationMinutes,
    ]));
  }

  // ----- Tiện ích -----

  void _emit(DriverEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _tickTimer?.cancel();
    unawaited(_gpsSubscription?.cancel());
    _hub?.dispose();
    unawaited(_events.close());
    super.dispose();
  }
}
