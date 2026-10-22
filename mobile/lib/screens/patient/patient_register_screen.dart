import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/geo.dart';
import '../../models/patient_models.dart';
import '../../services/auth_service.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';
import 'otp_screen.dart';
import 'patient_login_screen.dart';

/// Đăng ký hồ sơ y tế. Các trường bắt buộc và giới hạn độ dài theo model PatientProfile của backend.
///
/// Dùng lại cho chức năng sửa hồ sơ ([PatientRegisterScreen.edit]): điền sẵn dữ liệu, khóa số điện thoại
/// (định danh đăng nhập), bấm lưu thì gọi [onSave] thay vì đăng ký và gửi OTP.
class PatientRegisterScreen extends StatefulWidget {
  const PatientRegisterScreen({super.key})
      : initial = null,
        onSave = null;

  const PatientRegisterScreen.edit({super.key, required PatientProfile profile, required this.onSave})
      : initial = profile;

  final PatientProfile? initial;

  /// Trả về câu báo lỗi, hoặc null nếu đã lưu.
  final Future<String?> Function(PatientRegistration form)? onSave;

  bool get isEditing => initial != null;

  @override
  State<PatientRegisterScreen> createState() => _PatientRegisterScreenState();
}

class _PatientRegisterScreenState extends State<PatientRegisterScreen> {
  static const List<String> _genders = ['Nam', 'Nữ', 'Khác'];

  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _history = TextEditingController();
  final _allergies = TextEditingController();
  final _contactName = TextEditingController();
  final _contactPhone = TextEditingController();

  String _gender = _genders.first;
  DateTime? _birthDate;
  bool _birthDateMissing = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final profile = widget.initial;
    if (profile == null) return;
    _fullName.text = profile.fullName;
    _phone.text = profile.phoneNumber;
    _address.text = profile.permanentAddress ?? '';
    _history.text = profile.medicalHistory ?? '';
    _allergies.text = profile.drugAllergies ?? '';
    _contactName.text = profile.emergencyContactName ?? '';
    _contactPhone.text = profile.emergencyContactPhone ?? '';
    _birthDate = profile.birthDate;
    if (_genders.contains(profile.gender)) _gender = profile.gender!;
  }

  @override
  void dispose() {
    for (final controller in [
      _fullName,
      _phone,
      _address,
      _history,
      _allergies,
      _contactName,
      _contactPhone,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'Chọn ngày sinh',
    );
    if (picked != null) {
      setState(() {
        _birthDate = picked;
        _birthDateMissing = false;
      });
    }
  }

  Future<void> _submit() async {
    final valid = _formKey.currentState!.validate();
    final birthDate = _birthDate;
    if (birthDate == null) setState(() => _birthDateMissing = true);
    if (!valid || birthDate == null) return;

    String? optional(TextEditingController controller) {
      final text = controller.text.trim();
      return text.isEmpty ? null : text;
    }

    final form = PatientRegistration(
      fullName: _fullName.text.trim(),
      phoneNumber: _phone.text.trim(),
      birthDate: birthDate,
      gender: _gender,
      permanentAddress: _address.text.trim(),
      medicalHistory: optional(_history),
      drugAllergies: optional(_allergies),
      emergencyContactName: _contactName.text.trim(),
      emergencyContactPhone: _contactPhone.text.trim(),
    );

    final navigator = Navigator.of(context);
    final onSave = widget.onSave;
    if (onSave != null) {
      setState(() {
        _busy = true;
        _error = null;
      });
      final error = await onSave(form);
      if (!mounted) return;
      if (error == null) {
        navigator.pop(true);
      } else {
        setState(() {
          _busy = false;
          _error = error;
        });
      }
      return;
    }

    final auth = AuthService(context.read<AppState>().api);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ticket = await auth.registerPatient(form);
      await navigator.push(MaterialPageRoute<void>(
        builder: (_) => OtpScreen(ticket: ticket, resend: () => auth.registerPatient(form)),
      ));
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
    final birthDate = _birthDate;
    return Scaffold(
      appBar: AppBar(title: Text(widget.isEditing ? 'Sửa hồ sơ y tế' : 'Đăng ký hồ sơ y tế')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const _SectionTitle('Thông tin cá nhân'),
              TextFormField(
                controller: _fullName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
                decoration: const InputDecoration(
                    labelText: 'Họ và tên *', prefixIcon: Icon(Icons.badge)),
                validator: (value) => _required(value, 'Nhập họ và tên'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phone,
                // Số điện thoại là định danh đăng nhập bằng OTP nên không cho sửa.
                readOnly: widget.isEditing,
                enabled: !widget.isEditing,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: InputDecoration(
                    labelText: 'Số điện thoại *',
                    prefixIcon: const Icon(Icons.phone),
                    helperText: widget.isEditing ? 'Số điện thoại dùng để đăng nhập, không đổi được' : null),
                validator: validatePhone,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickBirthDate,
                borderRadius: BorderRadius.circular(12),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Ngày sinh *',
                    prefixIcon: const Icon(Icons.cake),
                    errorText: _birthDateMissing ? 'Chọn ngày sinh' : null,
                  ),
                  child: Text(birthDate == null ? 'Chạm để chọn' : formatDate(birthDate)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Giới tính:'),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SegmentedButton<String>(
                      segments: [
                        for (final gender in _genders)
                          ButtonSegment(value: gender, label: Text(gender)),
                      ],
                      selected: {_gender},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          setState(() => _gender = selection.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(300)],
                decoration: const InputDecoration(
                    labelText: 'Địa chỉ thường trú *', prefixIcon: Icon(Icons.home)),
                validator: (value) => _required(value, 'Nhập địa chỉ thường trú'),
              ),
              const _SectionTitle('Thông tin y tế'),
              TextFormField(
                controller: _history,
                maxLines: 2,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                decoration: const InputDecoration(
                  labelText: 'Tiền sử bệnh',
                  hintText: 'Các bệnh đang điều trị (tim mạch, tiểu đường...)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _allergies,
                maxLines: 2,
                inputFormatters: [LengthLimitingTextInputFormatter(500)],
                decoration: const InputDecoration(
                  labelText: 'Dị ứng thuốc',
                  hintText: 'Nếu không có, để trống',
                ),
              ),
              const _SectionTitle('Người thân liên hệ khi khẩn cấp'),
              TextFormField(
                controller: _contactName,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.next,
                inputFormatters: [LengthLimitingTextInputFormatter(100)],
                decoration: const InputDecoration(
                    labelText: 'Họ tên người thân *', prefixIcon: Icon(Icons.group)),
                validator: (value) => _required(value, 'Nhập tên người thân'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _contactPhone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(11),
                ],
                decoration: const InputDecoration(
                    labelText: 'Số điện thoại người thân *',
                    prefixIcon: Icon(Icons.contact_phone)),
                validator: (value) =>
                    validatePhone(value, empty: 'Nhập số điện thoại người thân'),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
              ],
              const SizedBox(height: 22),
              PrimaryButton(
                label: widget.isEditing ? 'LƯU THAY ĐỔI' : 'ĐĂNG KÝ & NHẬN MÃ OTP',
                icon: widget.isEditing ? Icons.save : Icons.how_to_reg,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.titleMedium
            ?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700),
      ),
    );
  }
}
