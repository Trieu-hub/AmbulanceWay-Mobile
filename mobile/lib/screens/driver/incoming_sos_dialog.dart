import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_config.dart';
import '../../core/geo.dart';
import '../../models/driver_models.dart';
import '../../state/driver_controller.dart';

/// Hộp thoại "CA CẤP CỨU MỚI" có đếm ngược, giống popup 15 giây của bản web.
/// Đóng với kết quả true nếu tài xế bấm nhận ca.
class IncomingSosDialog extends StatefulWidget {
  const IncomingSosDialog({super.key, required this.controller, required this.request});

  final DriverController controller;
  final PendingCase request;

  @override
  State<IncomingSosDialog> createState() => _IncomingSosDialogState();
}

class _IncomingSosDialogState extends State<IncomingSosDialog> {
  int _secondsLeft = AppConfig.incomingSosSeconds;
  Timer? _timer;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_closeIfTaken);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_secondsLeft <= 1) {
        // Hết giờ: ca vẫn nằm trong hàng chờ để nhận sau.
        _close(false);
      } else {
        setState(() => _secondsLeft--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    widget.controller.removeListener(_closeIfTaken);
    super.dispose();
  }

  /// Tài xế khác vừa nhận ca này thì tự đóng hộp thoại.
  void _closeIfTaken() {
    final stillWaiting =
        widget.controller.pending.any((item) => item.caseId == widget.request.caseId);
    if (!stillWaiting) _close(false);
  }

  void _close(bool accepted) {
    // Hết giờ, bấm nút và "ca đã có người nhận" có thể đến gần như cùng lúc: chỉ đóng một lần.
    if (_closed || !mounted) return;
    _closed = true;
    _timer?.cancel();
    Navigator.of(context).pop(accepted);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final distanceKm = haversineKm(widget.controller.mapPosition, request.location);

    return AlertDialog(
      icon: Icon(Icons.emergency_share, color: theme.colorScheme.primary, size: 40),
      title: const Text('CA CẤP CỨU MỚI'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            // Vòng tròn vơi dần theo số giây còn lại.
            child: SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: _secondsLeft / AppConfig.incomingSosSeconds,
                    strokeWidth: 6,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
                  ),
                  Center(
                    child: Text(
                      '$_secondsLeft',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('giây còn lại để nhận ca')),
          const SizedBox(height: 16),
          Text(request.address, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(request.summary),
          const SizedBox(height: 6),
          Text(
            'Cách bạn khoảng ${formatDistance(distanceKm)} • ước tính ${formatMinutes(estimateMinutes(distanceKm))}',
            style: TextStyle(color: theme.hintColor),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(onPressed: () => _close(false), child: const Text('BỎ QUA')),
        FilledButton(onPressed: () => _close(true), child: const Text('NHẬN CA NGAY')),
      ],
    );
  }
}
