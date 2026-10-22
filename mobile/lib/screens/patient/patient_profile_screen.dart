import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../models/patient_models.dart';
import '../../state/app_state.dart';
import '../../state/patient_controller.dart';
import '../../widgets/common.dart';
import 'patient_register_screen.dart';

/// Hồ sơ y tế của bệnh nhân: xem, sửa và đăng xuất.
class PatientProfileScreen extends StatelessWidget {
  const PatientProfileScreen({super.key});

  Future<void> _edit(BuildContext context, PatientProfile profile) async {
    final controller = context.read<PatientController>();
    final messenger = ScaffoldMessenger.of(context);
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => PatientRegisterScreen.edit(profile: profile, onSave: controller.updateProfile),
    ));
    if (saved == true) {
      messenger.showSnackBar(const SnackBar(content: Text('Đã lưu hồ sơ y tế.')));
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final app = context.read<AppState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: const Text('Lần sau bạn cần nhập lại số điện thoại và mã OTP.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('HỦY')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ĐĂNG XUẤT')),
        ],
      ),
    );
    // AppGate tự đóng màn hình này và quay về màn hình chào.
    if (confirmed == true) await app.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<PatientController>().profile;
    if (profile == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final birthDate = profile.birthDate;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hồ sơ của tôi'),
        actions: [
          IconButton(
            tooltip: 'Sửa hồ sơ',
            icon: const Icon(Icons.edit),
            onPressed: () => _edit(context, profile),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(profile.fullName, style: Theme.of(context).textTheme.titleLarge),
                  Text('Mã hồ sơ: ${profile.id}',
                      style: TextStyle(color: Theme.of(context).hintColor)),
                  const SizedBox(height: 8),
                  InfoRow(icon: Icons.phone, label: 'Số điện thoại', value: profile.phoneNumber),
                  InfoRow(
                    icon: Icons.cake,
                    label: 'Ngày sinh',
                    value: birthDate == null ? 'Chưa cập nhật' : formatDate(birthDate),
                  ),
                  InfoRow(
                      icon: Icons.wc, label: 'Giới tính', value: profile.gender ?? 'Chưa cập nhật'),
                  InfoRow(
                      icon: Icons.home,
                      label: 'Địa chỉ thường trú',
                      value: profile.permanentAddress ?? 'Chưa cập nhật'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  InfoRow(
                      icon: Icons.medical_information,
                      label: 'Tiền sử bệnh',
                      value: profile.medicalHistory ?? 'Không ghi nhận'),
                  InfoRow(
                      icon: Icons.warning_amber,
                      label: 'Dị ứng thuốc',
                      value: profile.drugAllergies ?? 'Không ghi nhận'),
                  InfoRow(
                    icon: Icons.contact_phone,
                    label: 'Người thân liên hệ',
                    value: [
                      profile.emergencyContactName ?? 'Chưa cập nhật',
                      ?profile.emergencyContactPhone,
                    ].join(' • '),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: () => _edit(context, profile),
            icon: const Icon(Icons.edit_note),
            label: const Text('SỬA HỒ SƠ Y TẾ'),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('Máy chủ'),
              subtitle: Text(context.watch<AppState>().baseUrl),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout),
            label: const Text('ĐĂNG XUẤT'),
          ),
        ],
      ),
    );
  }
}
