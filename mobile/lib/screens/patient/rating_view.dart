import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/patient_models.dart';
import '../../widgets/app_map.dart';
import '../../widgets/common.dart';

/// Form đánh giá sau khi ca hoàn thành - 5 tiêu chí giống bản web.
class RatingView extends StatefulWidget {
  const RatingView({super.key, required this.onSubmit, required this.onSkip});

  /// Gửi đánh giá; trả về câu báo lỗi hoặc null nếu thành công.
  final Future<String?> Function(RatingForm form) onSubmit;
  final VoidCallback onSkip;

  @override
  State<RatingView> createState() => _RatingViewState();
}

class _RatingViewState extends State<RatingView> {
  final _comment = TextEditingController();
  int _overall = 5;
  int _responseTime = 5;
  int _attitude = 5;
  int _vehicle = 5;
  int _handling = 5;
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final comment = _comment.text.trim();
    final error = await widget.onSubmit(RatingForm(
      overall: _overall,
      responseTime: _responseTime,
      driverAttitude: _attitude,
      vehicleCondition: _vehicle,
      situationHandling: _handling,
      comment: comment.isEmpty ? null : comment,
    ));
    if (!mounted) return;
    setState(() => _busy = false);
    showAppSnack(context, error ?? 'Cảm ơn bạn đã đánh giá!', isError: error != null);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Icon(Icons.check_circle, size: 64, color: MapColors.hospital),
        const SizedBox(height: 10),
        Text(
          'Đã hoàn thành cấp cứu',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        Text(
          'Nhờ bạn đánh giá để chúng tôi nâng cao chất lượng cứu trợ.',
          textAlign: TextAlign.center,
          style: TextStyle(color: theme.hintColor),
        ),
        const SizedBox(height: 16),
        _StarRow(
          label: 'Đánh giá tổng thể',
          value: _overall,
          size: 40,
          onChanged: (value) => setState(() => _overall = value),
        ),
        const Divider(height: 28),
        _StarRow(
          label: 'Thời gian xe đến',
          value: _responseTime,
          onChanged: (value) => setState(() => _responseTime = value),
        ),
        _StarRow(
          label: 'Thái độ kíp tài xế & y tế',
          value: _attitude,
          onChanged: (value) => setState(() => _attitude = value),
        ),
        _StarRow(
          label: 'Tình trạng xe cứu thương',
          value: _vehicle,
          onChanged: (value) => setState(() => _vehicle = value),
        ),
        _StarRow(
          label: 'Khả năng xử lý tình huống',
          value: _handling,
          onChanged: (value) => setState(() => _handling = value),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _comment,
          maxLines: 3,
          inputFormatters: [LengthLimitingTextInputFormatter(1000)],
          decoration: const InputDecoration(labelText: 'Ý kiến đóng góp thêm'),
        ),
        const SizedBox(height: 18),
        PrimaryButton(
          label: 'GỬI ĐÁNH GIÁ',
          icon: Icons.send,
          color: MapColors.hospital,
          busy: _busy,
          onPressed: _submit,
        ),
        TextButton(onPressed: _busy ? null : widget.onSkip, child: const Text('Bỏ qua')),
      ],
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.label,
    required this.value,
    required this.onChanged,
    this.size = 30,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var star = 1; star <= 5; star++)
                IconButton(
                  tooltip: '$star sao',
                  visualDensity: VisualDensity.compact,
                  iconSize: size,
                  onPressed: () => onChanged(star),
                  icon: Icon(
                    star <= value ? Icons.star : Icons.star_border,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
