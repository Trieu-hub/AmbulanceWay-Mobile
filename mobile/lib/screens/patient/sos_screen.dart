import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/app_config.dart';
import '../../core/geo.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../state/patient_controller.dart';
import '../../widgets/app_map.dart';
import '../../widgets/common.dart';
import 'location_picker_screen.dart';
import 'patient_profile_screen.dart';

/// Các loại khẩn cấp - cùng danh sách với form SOS của bản web.
const List<String> kEmergencyTypes = [
  'Tai nạn giao thông',
  'Đột quỵ / Tai biến',
  'Ngưng tuần hoàn / Đau tim',
  'Khó thở cấp tính',
  'Khác',
];

/// Màn hình chính của bệnh nhân: xác định vị trí và phát tín hiệu SOS.
class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  final _location = LocationService();
  final _geocoding = GeocodingService();
  final _address = TextEditingController();
  final _description = TextEditingController();

  String _type = kEmergencyTypes.first;
  LatLng? _position;
  bool _locating = false;

  /// Người dùng đã tự sửa ô địa chỉ thì không ghi đè bằng địa chỉ tra từ tọa độ nữa.
  bool _addressEdited = false;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _address.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    final position = await _location.current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position != null) {
      _setPosition(position);
    } else if (_position == null) {
      showAppSnack(
        context,
        'Không lấy được vị trí GPS. Hãy chọn vị trí trên bản đồ.',
        isError: true,
      );
    }
  }

  void _setPosition(LatLng position) {
    setState(() => _position = position);
    _fillAddress(position);
  }

  Future<void> _fillAddress(LatLng position) async {
    if (_addressEdited && _address.text.trim().isNotEmpty) return;
    final found = await _geocoding.reverse(position);
    // Bỏ kết quả nếu trong lúc chờ người dùng đã đổi vị trí hoặc tự gõ địa chỉ.
    if (!mounted || found == null || _position != position) return;
    if (_addressEdited && _address.text.trim().isNotEmpty) return;
    _address.text = found;
  }

  Future<void> _pickOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(initial: _position ?? AppConfig.defaultCenter),
      ),
    );
    if (picked != null && mounted) {
      // Vị trí mới thì địa chỉ cũ không còn đúng: tra lại.
      _addressEdited = false;
      _address.clear();
      _setPosition(picked);
    }
  }

  Future<void> _send() async {
    final position = _position;
    if (position == null) {
      showAppSnack(
        context,
        'Chưa có vị trí. Hãy chọn vị trí trên bản đồ trước khi gửi.',
        isError: true,
      );
      return;
    }
    // Trong lúc khẩn cấp không bắt người dùng gõ: để trống thì gửi tọa độ và mô tả mặc định.
    final address = _address.text.trim().isEmpty
        ? 'Vị trí GPS: ${formatCoordinates(position)}'
        : _address.text.trim();
    final description = _description.text.trim().isEmpty
        ? 'Không có mô tả thêm'
        : _description.text.trim();

    final controller = context.read<PatientController>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.sos, color: MapColors.patient, size: 40),
        title: const Text('Gửi tín hiệu SOS?'),
        content: Text('Xe cấp cứu sẽ được điều tới:\n$address\n\nLoại khẩn cấp: $_type'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('HỦY'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('GỬI SOS'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final error = await controller.sendSos(
      emergencyType: _type,
      description: description,
      address: address,
      location: position,
    );
    if (error != null && mounted) showAppSnack(context, error, isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PatientController>();
    final profile = c.profile;
    final theme = Theme.of(context);
    final position = _position;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cấp cứu khẩn cấp'),
        actions: [
          if (profile != null)
            IconButton(
              tooltip: 'Hồ sơ của tôi',
              icon: const Icon(Icons.account_circle),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChangeNotifierProvider<PatientController>.value(
                    value: c,
                    child: const PatientProfileScreen(),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile != null)
            Text('Xin chào, ${profile.fullName}', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 180,
                  child: position == null
                      ? ColoredBox(
                          color: const Color(0xFFECEFF1),
                          child: Center(
                            child: _locating
                                ? const CircularProgressIndicator()
                                : const Text('Chưa xác định được vị trí'),
                          ),
                        )
                      : GestureDetector(
                          onTap: _pickOnMap,
                          // Bản đồ xem trước không cho kéo; chạm để mở màn hình chọn vị trí.
                          child: AbsorbPointer(
                            child: AppMap(
                              key: ValueKey(position),
                              center: position,
                              zoom: 16,
                              markers: [
                                mapPin(
                                  position,
                                  icon: Icons.personal_injury,
                                  color: MapColors.patient,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _locating
                              ? 'Đang xác định vị trí…'
                              : position == null
                              ? 'Hãy chọn vị trí trên bản đồ'
                              : 'Vị trí: ${formatCoordinates(position)}',
                          style: TextStyle(
                            color: position == null && !_locating
                                ? theme.colorScheme.error
                                : theme.hintColor,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Lấy lại vị trí GPS',
                        onPressed: _locating ? null : _locate,
                        icon: const Icon(Icons.my_location),
                      ),
                      TextButton.icon(
                        onPressed: _pickOnMap,
                        icon: const Icon(Icons.edit_location_alt),
                        label: const Text('Chỉnh'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _address,
            onChanged: (_) => _addressEdited = true,
            inputFormatters: [LengthLimitingTextInputFormatter(300)],
            decoration: const InputDecoration(
              labelText: 'Địa chỉ cấp cứu',
              hintText: 'Số nhà, tên đường, phường/xã…',
              prefixIcon: Icon(Icons.place),
            ),
          ),
          const SizedBox(height: 14),
          Text('Loại khẩn cấp', style: theme.textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final type in kEmergencyTypes)
                ChoiceChip(
                  label: Text(type),
                  selected: _type == type,
                  onSelected: (_) => setState(() => _type = type),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _description,
            maxLines: 2,
            inputFormatters: [LengthLimitingTextInputFormatter(1000)],
            decoration: const InputDecoration(
              labelText: 'Mô tả tình trạng (không bắt buộc)',
              hintText: 'Bệnh nhân có tỉnh táo không? Đau ở đâu?',
            ),
          ),
          const SizedBox(height: 20),
          _Pulse(
            active: !c.sending,
            child: SizedBox(
              height: 64,
              child: FilledButton.icon(
                onPressed: c.sending ? null : _send,
                icon: c.sending
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const Icon(Icons.campaign, size: 28),
                label: Text(
                  c.sending ? 'ĐANG GỬI…' : 'PHÁT TÍN HIỆU SOS',
                  style: const TextStyle(fontSize: 18, letterSpacing: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => callPhone(AppConfig.emergencyNumber),
            icon: const Icon(Icons.phone),
            label: const Text('Hoặc gọi trực tiếp 115'),
          ),
        ],
      ),
    );
  }
}

/// Vầng sáng đỏ lan ra rồi tắt dần quanh nút SOS để nút nổi bật trên màn hình.
class _Pulse extends StatefulWidget {
  const _Pulse({required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(_Pulse oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, child) {
        final t = Curves.easeOut.transform(_controller.value);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: MapColors.patient.withValues(alpha: 0.45 * (1 - t)),
                spreadRadius: 14 * t,
                blurRadius: 6,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
