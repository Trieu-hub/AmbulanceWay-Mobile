import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../models/patient_models.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Nhập mã OTP 6 số. Đúng mã thì đăng nhập luôn với vai trò bệnh nhân.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.ticket, required this.resend});

  final OtpTicket ticket;

  /// Xin mã mới (đăng nhập hay đăng ký thì cách xin khác nhau).
  final Future<OtpTicket> Function() resend;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  late OtpTicket _ticket = widget.ticket;
  bool _busy = false;
  bool _resending = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Mã OTP gồm 6 chữ số');
      return;
    }
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await AuthService(app.api).verifyPatientOtp(_ticket.phoneNumber, code);
      // AppGate tự chuyển sang màn hình bệnh nhân khi có phiên đăng nhập.
      await app.signIn(session);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() async {
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      final ticket = await widget.resend();
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _code.clear();
      });
      showAppSnack(context, 'Đã tạo mã OTP mới.');
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final devOtp = _ticket.devOtp;
    return Scaffold(
      appBar: AppBar(title: const Text('Xác thực OTP')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Nhập mã 6 số gửi tới ${_ticket.phoneNumber}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge,
            ),
            Text(
              'Mã có hiệu lực trong ${_ticket.expiresInSeconds ~/ 60} phút.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.hintColor),
            ),
            if (devOtp != null) ...[
              const SizedBox(height: 16),
              // Backend V1 chưa nối nhà cung cấp SMS nên trả mã về để thử nghiệm.
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE082)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.science, color: Color(0xFFF57F17)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('Bản thử nghiệm chưa gửi SMS. Mã OTP của bạn: $devOtp'),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _code.text = devOtp),
                      child: const Text('Điền'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 20),
            TextField(
              controller: _code,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              autofocus: true,
              style: const TextStyle(fontSize: 26, letterSpacing: 10, fontWeight: FontWeight.w700),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => _verify(),
              decoration: const InputDecoration(hintText: '••••••'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center, style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'XÁC NHẬN',
              icon: Icons.verified_user,
              busy: _busy,
              onPressed: _verify,
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy || _resending ? null : _resend,
              child: Text(_resending ? 'Đang tạo mã mới…' : 'Gửi lại mã'),
            ),
          ],
        ),
      ),
    );
  }
}
