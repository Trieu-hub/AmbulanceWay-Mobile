import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../models/driver_models.dart';
import '../../models/hospital.dart';
import '../../models/route_plan.dart';
import '../../services/hub_client.dart';
import '../../state/app_state.dart';
import '../../state/driver_controller.dart';
import '../../widgets/app_map.dart';
import '../../widgets/common.dart';

/// Tab "Nhiệm vụ": vào ca trực, bản đồ, hàng chờ SOS và các bước của một ca.
class DriverMissionTab extends StatelessWidget {
  const DriverMissionTab({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();

    if (c.loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nhiệm vụ')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final profile = c.profile;
    if (profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Nhiệm vụ')),
        body: ErrorRetry(
          message: c.loadError ?? 'Không tải được thông tin tài xế.',
          onRetry: c.init,
          secondaryLabel: 'Đăng xuất',
          onSecondary: () => context.read<AppState>().signOut(),
        ),
      );
    }
    return c.onDuty ? const _OnDutyView() : _OffDutyView(profile: profile);
  }
}

/// Màn hình khi đang trong ca: bản đồ ở trên, bảng điều khiển nhiệm vụ ở dưới.
/// Tách riêng để MapController được tạo và hủy cùng với bản đồ.
class _OnDutyView extends StatefulWidget {
  const _OnDutyView();

  @override
  State<_OnDutyView> createState() => _OnDutyViewState();
}

class _OnDutyViewState extends State<_OnDutyView> {
  final MapController _map = MapController();
  late final DriverController _controller;
  bool _mapReady = false;

  /// Khung nhìn bản đồ đã canh theo nội dung nào (để không giật camera mỗi lần GPS cập nhật).
  String? _cameraKey;

  @override
  void initState() {
    super.initState();
    _controller = context.read<DriverController>()..addListener(_syncCamera);
  }

  @override
  void dispose() {
    _controller.removeListener(_syncCamera);
    _map.dispose();
    super.dispose();
  }

  /// Canh lại bản đồ khi nội dung chính đổi: có lộ trình mới, danh sách bệnh viện, hoặc lần đầu có GPS.
  void _syncCamera() {
    if (!_mapReady || !mounted) return;
    final c = _controller;
    final mission = c.mission;
    final route = c.route;

    String key;
    List<LatLng> points;
    if (mission != null && mission.phase == MissionPhase.pickedUp) {
      key = 'hospitals-${mission.caseId}-${c.hospitalOptions.length}';
      points = [c.mapPosition, ...c.hospitalOptions.map((h) => h.location)];
    } else if (mission != null && route != null) {
      key = 'route-${mission.caseId}-${mission.phase.name}-${mission.hospital?.name}';
      points = route.points;
    } else if (mission == null) {
      key = 'idle-${c.hasRealPosition}-${c.simulateLocation}';
      points = [c.mapPosition];
    } else {
      return; // đang chờ tính lộ trình
    }

    if (key == _cameraKey) return;
    _cameraKey = key;
    _showPoints(points);
  }

  void _showPoints(List<LatLng> points) {
    if (!_mapReady || points.isEmpty) return;
    if (points.length == 1) {
      _map.move(points.first, 15);
    } else {
      _map.fitCamera(
        CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(56), maxZoom: 17),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final mission = c.mission;
    return Scaffold(
      appBar: AppBar(
        title: Text(mission == null ? 'Sẵn sàng trực ca' : 'Đang làm nhiệm vụ'),
        actions: [
          IconButton(
            tooltip: 'Ca đang chờ',
            onPressed: () => _showPendingSheet(context, c),
            icon: Badge(
              isLabelVisible: c.pending.isNotEmpty,
              label: Text('${c.pending.length}'),
              backgroundColor: Colors.white,
              textColor: Theme.of(context).colorScheme.primary,
              child: const Icon(Icons.notifications),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _StatusBanners(controller: c),
          Expanded(
            child: Stack(
              children: [
                SmoothPosition(
                  position: c.mapPosition,
                  builder: (vehicle) => AppMap(
                    controller: _map,
                    center: c.mapPosition,
                    markers: _markers(context, c, vehicle),
                    polylines: _polylines(c),
                    onLongPress: c.simulateLocation ? c.moveSimulatedPosition : null,
                    onMapReady: () {
                      _mapReady = true;
                      _syncCamera();
                    },
                  ),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'driver-recenter',
                    tooltip: 'Về vị trí xe',
                    onPressed: () => _showPoints([c.mapPosition]),
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          _MissionPanel(controller: c),
        ],
      ),
    );
  }

  List<Marker> _markers(BuildContext context, DriverController c, LatLng vehicle) {
    final mission = c.mission;
    return [
      if (mission == null)
        for (final request in c.pending)
          Marker(
            point: request.location,
            width: 44,
            height: 44,
            child: GestureDetector(
              onTap: () => _confirmAccept(context, c, request),
              child: const _PendingPin(),
            ),
          ),
      if (mission != null && mission.phase == MissionPhase.toPatient)
        mapPin(mission.patientLocation, icon: Icons.personal_injury, color: MapColors.patient),
      if (mission != null && mission.phase == MissionPhase.pickedUp)
        for (final hospital in c.hospitalOptions)
          mapPin(
            hospital.location,
            icon: Icons.local_hospital,
            color: MapColors.hospital,
            size: 36,
          ),
      if (mission?.phase == MissionPhase.toHospital && mission?.hospital != null)
        mapPin(mission!.hospital!.location, icon: Icons.local_hospital, color: MapColors.hospital),
      mapPin(vehicle, icon: Icons.airport_shuttle, color: MapColors.ambulance),
    ];
  }

  List<Polyline> _polylines(DriverController c) {
    final route = c.route;
    final mission = c.mission;
    if (route == null || mission == null) return const [];
    return [
      Polyline(
        points: route.points,
        strokeWidth: 5,
        color: mission.phase == MissionPhase.toHospital ? MapColors.hospital : MapColors.patient,
        // Lộ trình ước lượng (không gọi được dịch vụ dẫn đường) vẽ nét đứt.
        pattern: route.isEstimate
            ? StrokePattern.dashed(segments: const [12, 10])
            : const StrokePattern.solid(),
      ),
    ];
  }
}

// ---------------------------------------------------------------------------
// Các thao tác có hộp thoại xác nhận
// ---------------------------------------------------------------------------

Future<void> _confirmAccept(BuildContext context, DriverController c, PendingCase request) async {
  final distanceKm = haversineKm(c.mapPosition, request.location);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Nhận ca này?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(request.address, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(request.summary),
          const SizedBox(height: 6),
          Text('Cách bạn khoảng ${formatDistance(distanceKm)}'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('HỦY'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('BẮT ĐẦU'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final error = await c.acceptCase(request);
  if (error != null && context.mounted) showAppSnack(context, error, isError: true);
}

Future<void> _confirmComplete(BuildContext context, DriverController c) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Hoàn thành nhiệm vụ?'),
      content: const Text('Ca cấp cứu sẽ được đóng và ghi vào lịch sử chuyến.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('CHƯA'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('XÁC NHẬN'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  final error = await c.completeMission();
  if (!context.mounted) return;
  showAppSnack(context, error ?? 'Đã hoàn thành nhiệm vụ.', isError: error != null);
}

Future<void> _run(BuildContext context, Future<String?> Function() action) async {
  final error = await action();
  if (error != null && context.mounted) showAppSnack(context, error, isError: true);
}

void _showPendingSheet(BuildContext context, DriverController c) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ListenableBuilder(
      listenable: c,
      builder: (_, _) {
        if (c.pending.isEmpty) {
          return const SizedBox(
            height: 160,
            child: Center(child: Text('Hiện không có ca nào đang chờ.')),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          itemCount: c.pending.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (_, index) {
            final request = c.pending[index];
            final created = request.createdAt;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFFFE0B2),
                child: Icon(Icons.sos, color: Color(0xFFE65100)),
              ),
              title: Text(request.address, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                [
                  request.summary,
                  '${formatDistance(haversineKm(c.mapPosition, request.location))}'
                      '${created == null ? '' : ' • ${formatTime(created)}'}'
                      '${request.assignedToMe ? ' • Admin chỉ định cho bạn' : ''}',
                ].join('\n'),
              ),
              isThreeLine: true,
              trailing: const Icon(Icons.chevron_right),
              onTap: c.mission != null
                  ? null
                  : () {
                      Navigator.of(sheetContext).pop();
                      _confirmAccept(context, c, request);
                    },
            );
          },
        );
      },
    ),
  );
}

void _showStepsSheet(BuildContext context, RoutePlan route) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: route.steps.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final step = route.steps[index];
        return ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(radius: 14, child: Text('${index + 1}')),
          title: Text(step.instruction),
          trailing: step.distanceMeters > 0 ? Text(formatMeters(step.distanceMeters)) : null,
        );
      },
    ),
  );
}

void _showHospitalSheet(BuildContext context, DriverController c) {
  if (c.hospitalOptions.isEmpty) c.loadHospitalOptions();
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ListenableBuilder(
          listenable: c,
          builder: (_, _) =>
              _HospitalChoices(controller: c, onChosen: () => Navigator.of(sheetContext).pop()),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Các mảnh giao diện
// ---------------------------------------------------------------------------

class _OffDutyView extends StatelessWidget {
  const _OffDutyView({required this.profile});

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ca trực')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Xin chào, ${profile.driverName}',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 10),
                  InfoRow(icon: Icons.directions_car, label: 'Xe', value: profile.vehicle),
                  InfoRow(icon: Icons.home_work, label: 'Trạm trực', value: profile.station),
                  InfoRow(icon: Icons.phone, label: 'Điện thoại', value: profile.phone),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Bạn chưa vào ca. Khi bắt đầu ca trực, app sẽ gửi vị trí xe lên trung tâm '
            'và nhận tín hiệu SOS của các ca gần bạn.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'BẮT ĐẦU CA TRỰC',
            icon: Icons.play_arrow,
            busy: c.busy,
            onPressed: () => _run(context, c.startDuty),
          ),
        ],
      ),
    );
  }
}

class _PendingPin extends StatelessWidget {
  const _PendingPin();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFE65100),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2))],
      ),
      child: const Icon(Icons.sos, color: Colors.white, size: 22),
    );
  }
}

/// Dải cảnh báo phía trên bản đồ: mất kết nối, không có GPS, đang mô phỏng vị trí.
class _StatusBanners extends StatelessWidget {
  const _StatusBanners({required this.controller});

  final DriverController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final issue = c.locationIssue;
    return Column(
      children: [
        if (c.hubStatus != HubStatus.connected)
          const _Banner(
            color: Color(0xFFFFF3CD),
            icon: Icons.cloud_off,
            text:
                'Chưa kết nối được kênh realtime, đang thử lại… Bạn có thể chưa nhận được SOS mới.',
          ),
        if (c.simulateLocation)
          const _Banner(
            color: Color(0xFFE3F2FD),
            icon: Icons.touch_app,
            text: 'Chế độ mô phỏng: nhấn giữ trên bản đồ để đặt vị trí xe.',
          )
        else if (issue != null)
          _Banner(
            color: const Color(0xFFECEFF1),
            icon: Icons.location_off,
            text: c.gpsPosition == null
                ? '${issue.message} Bản đồ đang dùng vị trí trạm.'
                : '${issue.message} Đang dùng vị trí GPS gần nhất.',
            actionLabel: 'Thử lại',
            onAction: c.startLocation,
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.color,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  final Color color;
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.black87),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.black87)),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Bảng điều khiển dưới bản đồ, nội dung đổi theo chặng của nhiệm vụ.
/// Phần thông tin cuộn được, còn nút thao tác chính luôn nằm cố định ở đáy để không bị che.
class _MissionPanel extends StatelessWidget {
  const _MissionPanel({required this.controller});

  final DriverController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final mission = c.mission;
    final (List<Widget> details, List<Widget> actions) = switch (mission?.phase) {
      null => _idle(context, c),
      MissionPhase.toPatient => _toPatient(context, c, mission!),
      MissionPhase.pickedUp => _pickedUp(context, c, mission!),
      MissionPhase.toHospital => _toHospital(context, c, mission!),
    };

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
      ),
      // Bảng co giãn mượt khi nội dung đổi theo chặng của nhiệm vụ.
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: details),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }

  (List<Widget>, List<Widget>) _idle(BuildContext context, DriverController c) => (
    [
      const _PanelHeader(color: Color(0xFF2E7D32), title: 'SẴN SÀNG TRỰC CA'),
      const SizedBox(height: 4),
      Text(
        c.pending.isEmpty
            ? 'Đang chờ tín hiệu cấp cứu…'
            : 'Có ${c.pending.length} ca đang chờ người nhận.',
        style: TextStyle(color: Theme.of(context).hintColor),
      ),
    ],
    [
      if (c.pending.isNotEmpty) ...[
        PrimaryButton(
          label: 'XEM CA ĐANG CHỜ (${c.pending.length})',
          icon: Icons.notifications_active,
          onPressed: () => _showPendingSheet(context, c),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: c.busy ? null : () => _run(context, c.endDuty),
        icon: const Icon(Icons.stop_circle_outlined),
        label: const Text('KẾT THÚC CA TRỰC'),
      ),
    ],
  );

  (List<Widget>, List<Widget>) _toPatient(
    BuildContext context,
    DriverController c,
    Mission mission,
  ) => (
    [
      const _PanelHeader(color: MapColors.patient, title: 'ĐANG ĐẾN CHỖ BỆNH NHÂN'),
      const SizedBox(height: 8),
      Text(mission.address, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(mission.summary),
      _PatientBlock(patient: mission.patient),
      _RouteSummary(controller: c),
    ],
    [
      PrimaryButton(
        label: 'ĐÃ ĐÓN BỆNH NHÂN',
        icon: Icons.how_to_reg,
        color: const Color(0xFFF57C00),
        busy: c.busy,
        onPressed: () => _run(context, c.markPickedUp),
      ),
    ],
  );

  (List<Widget>, List<Widget>) _pickedUp(
    BuildContext context,
    DriverController c,
    Mission mission,
  ) => (
    [
      const _PanelHeader(color: Color(0xFFF57C00), title: 'ĐÃ ĐÓN BỆNH NHÂN'),
      const SizedBox(height: 6),
      const Text('Chọn bệnh viện để dẫn đường. Bệnh viện có dấu ✓ đã được trung tâm báo trước.'),
      const SizedBox(height: 6),
      _HospitalChoices(controller: c),
    ],
    [
      OutlinedButton.icon(
        onPressed: c.busy ? null : () => _confirmComplete(context, c),
        icon: const Icon(Icons.check_circle_outline),
        label: const Text('HOÀN THÀNH NHIỆM VỤ'),
      ),
    ],
  );

  (List<Widget>, List<Widget>) _toHospital(
    BuildContext context,
    DriverController c,
    Mission mission,
  ) {
    final hospital = mission.hospital;
    final room = hospital?.assignedRoom;
    return (
      [
        const _PanelHeader(color: MapColors.hospital, title: 'ĐANG VỀ BỆNH VIỆN'),
        const SizedBox(height: 8),
        Text(
          hospital?.name ?? 'Bệnh viện',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        if (hospital != null && hospital.address.isNotEmpty) Text(hospital.address),
        if (room != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Đưa bệnh nhân vào: $room',
              style: const TextStyle(color: MapColors.hospital, fontWeight: FontWeight.w600),
            ),
          ),
        _PatientBlock(patient: mission.patient),
        _RouteSummary(controller: c),
      ],
      [
        PrimaryButton(
          label: 'HOÀN THÀNH NHIỆM VỤ',
          icon: Icons.check_circle,
          color: MapColors.hospital,
          busy: c.busy,
          onPressed: () => _confirmComplete(context, c),
        ),
        TextButton(
          onPressed: c.busy ? null : () => _showHospitalSheet(context, c),
          child: const Text('Đổi bệnh viện'),
        ),
      ],
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.color, required this.title});

  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w800, letterSpacing: 0.5),
        ),
      ],
    );
  }
}

/// Thông tin bệnh nhân và hồ sơ y tế (chỉ có sau khi nhận ca).
class _PatientBlock extends StatelessWidget {
  const _PatientBlock({required this.patient});

  final PatientInfo? patient;

  @override
  Widget build(BuildContext context) {
    final p = patient;
    if (p == null) return const SizedBox(height: 8);

    final age = p.age;
    final details = [if (age != null) '$age tuổi', if (p.gender != null) p.gender!].join(' • ');
    final contactPhone = p.emergencyContactPhone;

    return Theme(
      // Bỏ hai đường kẻ mặc định của ExpansionTile.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        leading: const Icon(Icons.person),
        title: Text(p.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(details.isEmpty ? 'Xem hồ sơ y tế' : '$details • xem hồ sơ y tế'),
        trailing: isCallablePhone(p.phoneNumber)
            ? IconButton(
                tooltip: 'Gọi bệnh nhân',
                icon: const Icon(Icons.call, color: MapColors.hospital),
                onPressed: () => callPhone(p.phoneNumber),
              )
            : null,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoRow(
            icon: Icons.medical_information,
            label: 'Tiền sử bệnh',
            value: p.medicalHistory ?? 'Không ghi nhận',
          ),
          InfoRow(
            icon: Icons.warning_amber,
            label: 'Dị ứng thuốc',
            value: p.drugAllergies ?? 'Không ghi nhận',
          ),
          InfoRow(
            icon: Icons.contact_phone,
            label: 'Người thân',
            value: [
              p.emergencyContactName ?? 'Không ghi nhận',
              if (isCallablePhone(contactPhone)) contactPhone!,
            ].join(' • '),
          ),
        ],
      ),
    );
  }
}

class _RouteSummary extends StatelessWidget {
  const _RouteSummary({required this.controller});

  final DriverController controller;

  @override
  Widget build(BuildContext context) {
    final route = controller.route;
    final theme = Theme.of(context);

    if (route == null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text('Đang tính lộ trình…', style: TextStyle(color: theme.hintColor)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Metric(
              value: formatDistance(route.distanceKm),
              label: route.isEstimate ? 'Ước lượng' : 'Khoảng cách',
            ),
          ),
          Expanded(
            child: _Metric(value: formatMinutes(route.durationMinutes), label: 'Dự kiến'),
          ),
          if (route.steps.isNotEmpty)
            TextButton.icon(
              onPressed: () => _showStepsSheet(context, route),
              icon: const Icon(Icons.turn_right),
              label: const Text('Chỉ dẫn'),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: MapColors.patient,
          ),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      ],
    );
  }
}

/// Danh sách bệnh viện gần nhất để tài xế chốt nơi đưa bệnh nhân tới.
class _HospitalChoices extends StatelessWidget {
  const _HospitalChoices({required this.controller, this.onChosen});

  final DriverController controller;
  final VoidCallback? onChosen;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c.hospitalsLoading && c.hospitalOptions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (c.hospitalOptions.isEmpty) {
      return Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('Chưa có bệnh viện nào đang nhận bệnh trong hệ thống.'),
          ),
          TextButton.icon(
            onPressed: c.loadHospitalOptions,
            icon: const Icon(Icons.refresh),
            label: const Text('Tải lại'),
          ),
        ],
      );
    }
    return Column(
      children: [for (final hospital in c.hospitalOptions) _tile(context, c, hospital)],
    );
  }

  Widget _tile(BuildContext context, DriverController c, Hospital hospital) {
    final beds = hospital.availableBeds;
    final info = [
      formatDistance(haversineKm(c.mapPosition, hospital.location)),
      if (beds != null) '$beds giường trống',
    ].join(' • ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        hospital.notified ? Icons.check_circle : Icons.local_hospital,
        color: MapColors.hospital,
      ),
      title: Text(hospital.name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(info),
      trailing: FilledButton.tonal(
        onPressed: c.busy
            ? null
            : () async {
                final error = await c.chooseHospital(hospital);
                if (error != null) {
                  if (context.mounted) showAppSnack(context, error, isError: true);
                } else {
                  onChosen?.call();
                }
              },
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 38),
          padding: const EdgeInsets.symmetric(horizontal: 14),
        ),
        child: const Text('Đi tới'),
      ),
    );
  }
}
