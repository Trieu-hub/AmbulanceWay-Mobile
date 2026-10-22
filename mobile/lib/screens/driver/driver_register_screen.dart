import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Tài xế tự đăng ký tài khoản (cùng các trường với form đăng ký của bản web).
/// Đóng màn hình và trả về tên đăng nhập khi thành công.
class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _fullName = TextEditingController();
  final _vehicle = TextEditingController();
  final _license = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    _vehicle.dispose();
    _license.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final app = context.read<AppState>();
    final navigator = Navigator.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AuthService(app.api).registerDriver(
        username: _username.text,
        password: _password.text,
        fullName: _fullName.text,
        vehicleNo: _vehicle.text,
        licenseNo: _license.text,
      );
      navigator.pop(_username.text.trim());
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _required(String? value, String message) =>
      (value == null || value.trim().isEmpty) ? message : null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Đăng ký tài xế')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Họ và tên', prefixIcon: Icon(Icons.badge)),
                validator: (value) => _required(value, 'Nhập họ và tên'),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _username,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Tên đăng nhập', prefixIcon: Icon(Icons.person)),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Nhập tên đăng nhập';
                  if (text.length > 50) return 'Tối đa 50 ký tự';
                  if (text.contains(' ')) return 'Không dùng khoảng trắng';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _password,
                obscureText: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                    labelText: 'Mật khẩu', prefixIcon: Icon(Icons.lock)),
                validator: (value) =>
                    (value == null || value.trim().length < 6) ? 'Mật khẩu ít nhất 6 ký tự' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _vehicle,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Biển số xe',
                  hintText: '51A-123.45',
                  prefixIcon: Icon(Icons.directions_car),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Nhập biển số xe';
                  // Biển số được chép sang các cột giới hạn 20 ký tự (DutySessions, EmergencyCases).
                  if (text.length > 20) return 'Tối đa 20 ký tự';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _license,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Số giấy phép lái xe (không bắt buộc)',
                  prefixIcon: Icon(Icons.credit_card),
                ),
                validator: (value) =>
                    (value != null && value.trim().length > 50) ? 'Tối đa 50 ký tự' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: 'ĐĂNG KÝ',
                icon: Icons.person_add,
                busy: _busy,
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
