import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/geo.dart';
import '../../models/patient_models.dart';
import '../../services/hub_client.dart';
import '../../state/app_state.dart';
import '../../state/patient_controller.dart';
import '../../widgets/app_map.dart';
import '../../widgets/common.dart';
import 'rating_view.dart';

/// Theo dõi ca cấp cứu đang diễn ra: các bước, bản đồ xe đang tới, tài xế và bệnh viện.
class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PatientController>();
    final snapshot = c.activeCase;
    if (snapshot == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: Text('Ca cấp cứu #${snapshot.id}'),
        actions: [
          IconButton(
            tooltip: 'Gọi 115',
            icon: const Icon(Icons.phone_in_talk),
            onPressed: () => callPhone(AppConfig.emergencyNumber),
          ),
        ],
      ),
      body: Column(
        children: [
          _StepBar(current: snapshot.step, cancelled: snapshot.isCancelled),
          Expanded(child: _body(context, c, snapshot)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, PatientController c, CaseSnapshot snapshot) {
    if (snapshot.isCancelled) {
      return _Closed(
        icon: Icons.cancel,
        color: Theme.of(context).colorScheme.error,
        title: 'Ca cấp cứu đã bị hủy',
        message: 'Nếu vẫn cần hỗ trợ, hãy gửi lại tín hiệu SOS hoặc gọi 115.',
        onClose: c.closeCase,
      );
    }
    if (snapshot.isCompleted) {
      if (snapshot.hasRated) {
        return _Closed(
          icon: Icons.check_circle,
          color: MapColors.hospital,
          title: 'Ca cấp cứu đã hoàn thành',
          message: 'Cảm ơn bạn đã đánh giá dịch vụ.',
          onClose: c.closeCase,
        );
      }
      return RatingView(
        onSubmit: c.submitRating,
        onSkip: () async {
          await context.read<AppState>().rememberSkippedRating(snapshot.id);
          c.closeCase();
        },
      );
    }
    return _LiveView(snapshot: snapshot);
  }
}

/// Thanh 5 bước: Gửi SOS → Nhận ca → Đón bệnh → Về viện → Hoàn thành.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.current, required this.cancelled});

  final CaseStep current;
  final bool cancelled;

  static const List<(IconData, String)> _steps = [
    (Icons.cell_tower, 'Gửi SOS'),
    (Icons.airport_shuttle, 'Nhận ca'),
    (Icons.how_to_reg, 'Đón bệnh'),
    (Icons.local_hospital, 'Về viện'),
    (Icons.star, 'Hoàn thành'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = cancelled ? 0.0 : current.index / (_steps.length - 1);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 10),
      child: Stack(
        children: [
          // Đường nối các bước: phần đã qua tô xanh dần theo tiến trình.
          Positioned(
            top: 15,
            left: 0,
            right: 0,
            child: FractionallySizedBox(
              widthFactor: 0.8,
              child: Stack(
                children: [
                  Container(height: 4, color: Colors.grey.shade300),
                  AnimatedFractionallySizedBox(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    alignment: Alignment.centerLeft,
                    widthFactor: progress,
                    child: Container(height: 4, color: MapColors.hospital),
                  ),
                ],
              ),
            ),
          ),
          Row(
            children: [
              for (var index = 0; index < _steps.length; index++)
                Expanded(
                  child: _StepDot(
                    icon: _steps[index].$1,
                    label: _steps[index].$2,
                    // Các bước đã qua màu xanh, bước hiện tại màu đỏ, bước chưa tới màu xám.
                    color: cancelled
                        ? Colors.grey
                        : index < current.index
                        ? MapColors.hospital
                        : index == current.index
                        ? theme.colorScheme.primary
                        : Colors.grey.shade400,
                    highlighted: !cancelled && index == current.index,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  const _StepDot({
    required this.icon,
    required this.label,
    required this.color,
    required this.highlighted,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: highlighted
                ? [BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 10)]
                : const [],
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 11,
            color: highlighted ? color : Colors.black54,
            fontWeight: highlighted ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

/// Bản đồ trực tiếp và bảng thông tin trong lúc ca đang diễn ra.
class _LiveView extends StatefulWidget {
  const _LiveView({required this.snapshot});

  final CaseSnapshot snapshot;

  @override
  State<_LiveView> createState() => _LiveViewState();
}

class _LiveViewState extends State<_LiveView> {
  final MapController _map = MapController();
  bool _mapReady = false;

  /// Bản đồ đã canh cho những đối tượng nào (để không giật camera mỗi lần xe cập nhật vị trí).
  String? _cameraKey;

  @override
  void didUpdateWidget(_LiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Đang trong lượt build nên chưa được di chuyển bản đồ: chờ vẽ xong khung hình này.
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  List<LatLng> get _points {
    final snapshot = widget.snapshot;
    final hospital = snapshot.hospital?.location;
    final driver = snapshot.driverLocation;
    final pickedUp = snapshot.step.index >= CaseStep.pickedUp.index;
    return [
      // Sau khi đón, bệnh nhân ở trên xe: chỉ còn xe và bệnh viện là đáng theo dõi.
      if (!pickedUp || driver == null) snapshot.patientLocation,
      ?driver,
      ?hospital,
    ];
  }

  /// Canh lại khi xe hoặc bệnh viện mới xuất hiện trên bản đồ, hoặc ca sang bước khác.
  void _syncCamera() {
    if (!_mapReady || !mounted) return;
    final snapshot = widget.snapshot;
    final key =
        '${snapshot.step.name}-${snapshot.driverLocation != null}-${snapshot.hospital?.name}';
    if (key == _cameraKey) return;
    _cameraKey = key;
    _fit();
  }

  void _fit() {
    if (!_mapReady) return;
    final points = _points;
    if (points.length == 1) {
      _map.move(points.first, 16);
    } else {
      _map.fitCamera(
        CameraFit.coordinates(coordinates: points, padding: const EdgeInsets.all(64), maxZoom: 17),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PatientController>();
    final snapshot = widget.snapshot;
    final driver = snapshot.driverLocation;
    final hospital = snapshot.hospital;
    final pickedUp = snapshot.step.index >= CaseStep.pickedUp.index;

    return Column(
      children: [
        if (c.hubStatus != HubStatus.connected)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF3CD),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: const Text(
              'Đang kết nối kênh realtime… Trạng thái vẫn được cập nhật mỗi 10 giây.',
              style: TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              SmoothPosition(
                position: driver ?? snapshot.patientLocation,
                builder: (vehicle) => AppMap(
                  controller: _map,
                  center: snapshot.patientLocation,
                  zoom: 16,
                  markers: [
                    if (hospital != null)
                      mapPin(
                        hospital.location,
                        icon: Icons.local_hospital,
                        color: MapColors.hospital,
                      ),
                    if (!pickedUp || driver == null)
                      mapPin(
                        snapshot.patientLocation,
                        icon: Icons.personal_injury,
                        color: MapColors.patient,
                      ),
                    if (driver != null)
                      mapPin(vehicle, icon: Icons.airport_shuttle, color: MapColors.ambulance),
                  ],
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
                  heroTag: 'tracking-fit',
                  tooltip: 'Xem toàn cảnh',
                  onPressed: _fit,
                  child: const Icon(Icons.zoom_out_map),
                ),
              ),
            ],
          ),
        ),
        _InfoPanel(snapshot: snapshot, etaMinutes: c.etaMinutes, etaKm: c.etaKm),
      ],
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.snapshot, required this.etaMinutes, required this.etaKm});

  final CaseSnapshot snapshot;
  final int? etaMinutes;
  final double? etaKm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hospital = snapshot.hospital;
    final room = hospital?.assignedRoom;
    final minutes = etaMinutes;
    final km = etaKm;

    final (String title, String subtitle) = switch (snapshot.step) {
      CaseStep.sent => (
        'Đã gửi tín hiệu SOS',
        'Đang tìm xe cấp cứu gần bạn nhất. Vui lòng giữ máy.',
      ),
      CaseStep.accepted => ('Xe cấp cứu đang tới', snapshot.patientAddress),
      CaseStep.pickedUp => ('Đã đón bệnh nhân', 'Tài xế đang chọn bệnh viện tiếp nhận gần nhất.'),
      CaseStep.delivering => (
        'Đang về ${hospital?.name ?? 'bệnh viện'}',
        room == null ? (hospital?.address ?? '') : 'Phòng tiếp nhận: $room',
      ),
      CaseStep.completed => ('Đã hoàn thành', ''),
    };

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.4),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -2))],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            if (subtitle.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle, style: TextStyle(color: theme.hintColor)),
              ),
            if (snapshot.step == CaseStep.sent)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(
                  minHeight: 5,
                  borderRadius: BorderRadius.all(Radius.circular(4)),
                ),
              ),
            if (minutes != null && snapshot.step != CaseStep.sent)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  children: [
                    const Icon(Icons.schedule, size: 20, color: Color(0xFFF57C00)),
                    const SizedBox(width: 8),
                    Text(
                      snapshot.step == CaseStep.accepted
                          ? 'Dự kiến xe đến sau ${formatMinutes(minutes)}'
                          : 'Dự kiến tới viện sau ${formatMinutes(minutes)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (km != null) Text('  (${formatDistance(km)})'),
                  ],
                ),
              ),
            if (context.watch<PatientController>().canCancel) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: context.watch<PatientController>().cancelling
                      ? null
                      : () => confirmCancelCase(context),
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Hủy yêu cầu cấp cứu'),
                  style: TextButton.styleFrom(foregroundColor: theme.colorScheme.error),
                ),
              ),
            ],
            if (snapshot.hasDriver) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const CircleAvatar(
                    backgroundColor: Color(0xFFE3F2FD),
                    child: Icon(Icons.airport_shuttle, color: MapColors.ambulance),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          snapshot.driverName ?? 'Tài xế',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Xe ${snapshot.vehicle ?? '—'}',
                          style: TextStyle(color: theme.hintColor),
                        ),
                      ],
                    ),
                  ),
                  if (isCallablePhone(snapshot.driverPhone))
                    FilledButton.tonalIcon(
                      onPressed: () => callPhone(snapshot.driverPhone!),
                      icon: const Icon(Icons.call),
                      label: const Text('Gọi tài xế'),
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hỏi lý do rồi hủy yêu cầu SOS. Chỉ hiện khi xe chưa đón bệnh nhân.
Future<void> confirmCancelCase(BuildContext context) async {
  const reasons = [
    'Bệnh nhân đã ổn, không cần xe nữa',
    'Đã tự đến bệnh viện',
    'Gửi nhầm yêu cầu',
    'Lý do khác',
  ];
  final controller = context.read<PatientController>();
  final messenger = ScaffoldMessenger.of(context);
  var selected = reasons.first;
  final reason = await showDialog<String>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) => AlertDialog(
        title: const Text('Hủy yêu cầu cấp cứu?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tài xế đang được điều tới sẽ nhận thông báo hủy. Nếu tình trạng xấu đi, hãy gọi 115.'),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: selected,
              onChanged: (value) => setState(() => selected = value ?? selected),
              child: Column(
                children: [
                  for (final item in reasons)
                    RadioListTile<String>(
                      value: item,
                      title: Text(item),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('KHÔNG HỦY')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.of(dialogContext).pop(selected),
            child: const Text('HỦY YÊU CẦU'),
          ),
        ],
      ),
    ),
  );
  if (reason == null) return;
  final error = await controller.cancelCase(reason: reason);
  if (error != null) {
    messenger.showSnackBar(SnackBar(content: Text(error), backgroundColor: Colors.red.shade700));
  }
}

/// Màn hình kết thúc (đã hủy / đã hoàn thành và đã đánh giá).
class _Closed extends StatelessWidget {
  const _Closed({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
    required this.onClose,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            PrimaryButton(label: 'VỀ MÀN HÌNH CHÍNH', icon: Icons.home, onPressed: onClose),
          ],
        ),
      ),
    );
  }
}
