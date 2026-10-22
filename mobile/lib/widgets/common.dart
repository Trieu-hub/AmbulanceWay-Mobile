import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hiện thông báo ngắn ở cuối màn hình.
void showAppSnack(BuildContext context, String message, {bool isError = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      behavior: SnackBarBehavior.floating,
      backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
    ));
}

/// Mở trình gọi điện với số [phone]. Trả về false nếu thiết bị không gọi được.
Future<bool> callPhone(String phone) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (digits.isEmpty) return false;
  try {
    return await launchUrl(Uri(scheme: 'tel', path: digits));
  } on Exception {
    return false;
  }
}

/// Số điện thoại thật sự gọi được (backend dùng "000", "N/A" làm giá trị mặc định).
bool isCallablePhone(String? phone) {
  if (phone == null) return false;
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  return digits.length >= 8;
}

/// Nút chính chiếm hết chiều ngang, có trạng thái đang xử lý.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: color == null
            ? null
            : FilledButton.styleFrom(backgroundColor: color, foregroundColor: Colors.white),
        child: child,
      ),
    );
  }
}

/// Một dòng "nhãn: giá trị" có biểu tượng.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor)),
                const SizedBox(height: 2),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Khung báo lỗi kèm nút thử lại, dùng khi tải dữ liệu thất bại.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({
    super.key,
    required this.message,
    required this.onRetry,
    this.secondaryLabel,
    this.onSecondary,
  });

  final String message;
  final VoidCallback onRetry;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 56, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
