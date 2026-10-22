import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'otp_screen.dart';
import 'patient_register_screen.dart';

/// Số điện thoại hợp lệ để đăng ký / đăng nhập (9-11 chữ số).
String? validatePhone(String? value, {String empty = 'Nhập số điện thoại'}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return empty;
  if (!RegExp(r'^\d{9,11}$').hasMatch(text)) return 'Số điện thoại gồm 9-11 chữ số';
  return null;
}

/// Bệnh nhân đã có hồ sơ đăng nhập bằng số điện thoại + mã OTP.
class PatientLoginScreen extends StatefulWidget {
  const PatientLoginScreen({super.key});

  @override
  State<PatientLoginScreen> createState() => _PatientLoginScreenState();
}

class _PatientLoginScreenState extends State<PatientLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = AuthService(context.read<AppState>().api);
    final navigator = Navigator.of(context);
    final phone = _phone.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await auth.requestPatientOtp(phone);
      await navigator.push(MaterialPageRoute<void>(
        builder: (_) => OtpScreen(
          ticket: ticket,
          resend: () => auth.requestPatientOtp(phone),
        ),
      ));
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bệnh nhân / Người nhà')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              Icon(Icons.health_and_safety, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(
                'Đăng nhập bằng số điện thoại đã đăng ký hồ sơ y tế.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại',
                  hintText: '09xxxxxxxx',
                  prefixIcon: Icon(Icons.phone),
                ),
                validator: validatePhone,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'NHẬN MÃ OTP',
                icon: Icons.sms,
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => const PatientRegisterScreen())),
                icon: const Icon(Icons.assignment_ind),
                label: const Text('Chưa có hồ sơ? Đăng ký mới'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
