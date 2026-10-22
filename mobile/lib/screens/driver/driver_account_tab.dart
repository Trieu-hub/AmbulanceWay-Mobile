import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/geo.dart';
import '../../state/app_state.dart';
import '../../state/driver_controller.dart';
import '../../widgets/common.dart';

/// Tab "Tài khoản": hồ sơ tài xế, chế độ mô phỏng vị trí và đăng xuất.
class DriverAccountTab extends StatelessWidget {
  const DriverAccountTab({super.key});

  Future<void> _signOut(BuildContext context, DriverController c) async {
    final app = context.read<AppState>();
    if (c.mission != null) {
      showAppSnack(context, 'Hãy hoàn thành nhiệm vụ đang thực hiện trước khi đăng xuất.',
          isError: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Đăng xuất?'),
        content: Text(c.onDuty
            ? 'Ca trực hiện tại sẽ được kết thúc và bạn không còn nhận tín hiệu SOS.'
            : 'Bạn sẽ cần đăng nhập lại để vào ca.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('HỦY')),
          FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('ĐĂNG XUẤT')),
        ],
      ),
    );
    if (confirmed != true) return;

    if (c.onDuty) {
      // Kết thúc ca để máy chủ chuyển tài xế sang OFFLINE, không điều phối SOS cho máy đã thoát.
      final error = await c.endDuty();
      if (error != null) {
        if (context.mounted) showAppSnack(context, error, isError: true);
        return;
      }
    }
    await app.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<DriverController>();
    final app = context.watch<AppState>();
    final profile = c.profile;
    final dutyStart = c.dutyStartedAt;

    return Scaffold(
      appBar: AppBar(title: const Text('Tài khoản')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (profile != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(profile.driverName, style: Theme.of(context).textTheme.titleLarge),
                    Text('@${profile.username}',
                        style: TextStyle(color: Theme.of(context).hintColor)),
                    const SizedBox(height: 8),
                    InfoRow(icon: Icons.directions_car, label: 'Xe', value: profile.vehicle),
                    InfoRow(icon: Icons.home_work, label: 'Trạm trực', value: profile.station),
                    InfoRow(icon: Icons.phone, label: 'Điện thoại', value: profile.phone),
                    InfoRow(
                        icon: Icons.credit_card, label: 'Giấy phép lái xe', value: profile.licenseNo),
                    InfoRow(
                      icon: Icons.schedule,
                      label: 'Ca trực',
                      value: !c.onDuty
                          ? 'Chưa vào ca'
                          : dutyStart == null
                              ? 'Đang trong ca'
                              : 'Bắt đầu lúc ${formatDateTime(dutyStart)}',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Card(
            child: SwitchListTile(
              value: c.simulateLocation,
              onChanged: c.onDuty ? c.setSimulateLocation : null,
              secondary: const Icon(Icons.touch_app),
              title: const Text('Mô phỏng vị trí xe'),
              subtitle: const Text(
                  'Dùng khi demo trên máy tính hoặc máy ảo không có GPS: nhấn giữ trên bản đồ để di chuyển xe.'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.dns),
              title: const Text('Máy chủ'),
              subtitle: Text(app.baseUrl),
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: c.busy ? null : () => _signOut(context, c),
            icon: const Icon(Icons.logout),
            label: const Text('ĐĂNG XUẤT'),
          ),
        ],
      ),
    );
  }
}
