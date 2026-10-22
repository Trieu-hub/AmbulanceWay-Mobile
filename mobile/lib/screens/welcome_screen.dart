import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../core/app_config.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';
import 'driver/driver_login_screen.dart';
import 'patient/patient_login_screen.dart';
import 'server_settings_screen.dart';

/// Màn hình đầu tiên: chọn vai trò bệnh nhân hoặc tài xế.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  @override
  void initState() {
    super.initState();
    // Ví dụ "Phiên đăng nhập đã hết hạn" sau khi bị máy chủ từ chối token.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final notice = context.read<AppState>().takeNotice();
      if (notice != null) showAppSnack(context, notice, isError: true);
    });
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final theme = Theme.of(context);

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE53935), Color(0xFF8E1B1B)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Cài đặt máy chủ',
                  icon: const Icon(Icons.settings, color: Colors.white),
                  onPressed: () => _open(const ServerSettingsScreen()),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    // Nội dung trượt nhẹ lên và hiện dần khi mở app.
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 550),
                      curve: Curves.easeOutCubic,
                      builder: (_, t, child) => Opacity(
                        opacity: t,
                        child: Transform.translate(offset: Offset(0, 24 * (1 - t)), child: child),
                      ),
                      child: Column(
                        children: [
                          const CircleAvatar(
                            radius: 44,
                            backgroundColor: Colors.white,
                            child: Icon(Icons.emergency, size: 48, color: kBrandRed),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'AMBULANCE WAY',
                            style: theme.textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Hệ thống điều phối xe cấp cứu',
                            style: TextStyle(color: Colors.white70, fontSize: 15),
                          ),
                          const SizedBox(height: 36),
                          _RoleCard(
                            icon: Icons.sos,
                            title: 'Tôi cần cấp cứu',
                            subtitle: 'Gửi tín hiệu SOS và theo dõi xe đang tới',
                            onTap: () => _open(const PatientLoginScreen()),
                          ),
                          const SizedBox(height: 14),
                          _RoleCard(
                            icon: Icons.local_shipping,
                            title: 'Tôi là tài xế xe cấp cứu',
                            subtitle: 'Vào ca trực, nhận ca và dẫn đường',
                            onTap: () => _open(const DriverLoginScreen()),
                          ),
                          const SizedBox(height: 24),
                          TextButton.icon(
                            onPressed: () async {
                              final ok = await callPhone(AppConfig.emergencyNumber);
                              if (!ok && context.mounted) {
                                showAppSnack(
                                  context,
                                  'Thiết bị này không gọi điện được. Hãy gọi 115.',
                                );
                              }
                            },
                            icon: const Icon(Icons.phone, color: Colors.white),
                            label: const Text(
                              'Gọi cấp cứu 115',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
                child: Text(
                  'Máy chủ: ${app.baseUrl}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: kBrandRed.withValues(alpha: 0.1),
                child: Icon(icon, color: kBrandRed, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: Colors.black54)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.black38),
            ],
          ),
        ),
      ),
    );
  }
}
