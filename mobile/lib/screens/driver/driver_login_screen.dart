import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'driver_register_screen.dart';

/// Đăng nhập tài xế bằng tài khoản do Admin cấp hoặc tự đăng ký.
class DriverLoginScreen extends StatefulWidget {
  const DriverLoginScreen({super.key});

  @override
  State<DriverLoginScreen> createState() => _DriverLoginScreenState();
}

class _DriverLoginScreenState extends State<DriverLoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final session = await AuthService(app.api).loginDriver(_username.text, _password.text);
      // AppGate tự chuyển sang màn hình tài xế khi có phiên đăng nhập.
      await app.signIn(session);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openRegister() async {
    final username = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const DriverRegisterScreen()),
    );
    if (username != null && mounted) {
      _username.text = username;
      _password.clear();
      showAppSnack(context, 'Đăng ký thành công! Hãy đăng nhập.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng nhập tài xế')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 8),
              Icon(Icons.local_shipping, size: 64, color: theme.colorScheme.primary),
              const SizedBox(height: 24),
              TextFormField(
                controller: _username,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Tên đăng nhập',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? 'Nhập tên đăng nhập' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Mật khẩu',
                  prefixIcon: const Icon(Icons.lock),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Ẩn mật khẩu' : 'Hiện mật khẩu',
                    icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
                validator: (value) => (value == null || value.isEmpty) ? 'Nhập mật khẩu' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'ĐĂNG NHẬP',
                icon: Icons.login,
                busy: _busy,
                onPressed: _submit,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _busy ? null : _openRegister,
                child: const Text('Chưa có tài khoản? Đăng ký tài xế'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
