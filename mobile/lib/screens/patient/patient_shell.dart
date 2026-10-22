import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../../state/patient_controller.dart';
import '../../widgets/common.dart';
import 'sos_screen.dart';
import 'tracking_screen.dart';

/// Khung màn hình của bệnh nhân: gửi SOS khi chưa có ca, theo dõi khi đang có ca.
class PatientShell extends StatelessWidget {
  const PatientShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return ChangeNotifierProvider<PatientController>(
      create: (_) => PatientController(
        api: app.api,
        profileId: app.session?.patientProfileId ?? 0,
        skippedRatingCaseId: app.skippedRatingCaseId,
        notifier: context.read<AppNotifier>(),
      )..init(),
      child: const _PatientView(),
    );
  }
}

class _PatientView extends StatefulWidget {
  const _PatientView();

  @override
  State<_PatientView> createState() => _PatientViewState();
}

class _PatientViewState extends State<_PatientView> {
  StreamSubscription<PatientNotice>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<PatientController>().notices.listen((notice) {
      if (mounted) showAppSnack(context, notice.message, isError: notice.isError);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PatientController>();

    if (c.loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (c.profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('AmbulanceWay')),
        body: ErrorRetry(
          message: c.loadError ?? 'Không tải được hồ sơ bệnh nhân.',
          onRetry: c.init,
          secondaryLabel: 'Đăng xuất',
          onSecondary: () => context.read<AppState>().signOut(),
        ),
      );
    }
    return c.activeCase == null ? const SosScreen() : const TrackingScreen();
  }
}
