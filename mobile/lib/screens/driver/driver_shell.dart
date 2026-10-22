import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../../state/driver_controller.dart';
import '../../widgets/common.dart';
import 'driver_account_tab.dart';
import 'driver_history_tab.dart';
import 'driver_mission_tab.dart';
import 'incoming_sos_dialog.dart';

/// Khung màn hình của tài xế: Nhiệm vụ / Lịch sử / Tài khoản.
class DriverShell extends StatelessWidget {
  const DriverShell({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<DriverController>(
      create: (context) => DriverController(
        api: context.read<AppState>().api,
        notifier: context.read<AppNotifier>(),
      )..init(),
      child: const _DriverShellView(),
    );
  }
}

class _DriverShellView extends StatefulWidget {
  const _DriverShellView();

  @override
  State<_DriverShellView> createState() => _DriverShellViewState();
}

class _DriverShellViewState extends State<_DriverShellView> {
  int _tab = 0;
  StreamSubscription<DriverEvent>? _subscription;
  bool _sosDialogOpen = false;

  @override
  void initState() {
    super.initState();
    _subscription = context.read<DriverController>().events.listen(_onEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _onEvent(DriverEvent event) {
    if (!mounted) return;
    switch (event) {
      case IncomingSosEvent():
        _showIncomingSos(event);
      case HospitalAcceptedEvent(:final hospital):
        final room = hospital.assignedRoom;
        showAppSnack(
          context,
          room == null
              ? '${hospital.name} đã xác nhận tiếp nhận.'
              : '${hospital.name} đã xác nhận. Đưa bệnh nhân vào: $room',
        );
      case DriverNoticeEvent(:final message, :final isError):
        showAppSnack(context, message, isError: isError);
    }
  }

  Future<void> _showIncomingSos(IncomingSosEvent event) async {
    // Đang hỏi một ca khác: ca mới vẫn nằm trong hàng chờ, không chồng hộp thoại.
    if (_sosDialogOpen) return;
    final controller = context.read<DriverController>();
    _sosDialogOpen = true;
    unawaited(HapticFeedback.heavyImpact());
    unawaited(SystemSound.play(SystemSoundType.alert));

    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => IncomingSosDialog(controller: controller, request: event.request),
    );
    _sosDialogOpen = false;
    if (accepted != true || !mounted) return;

    final error = await controller.acceptCase(event.request);
    if (!mounted) return;
    if (error != null) {
      showAppSnack(context, error, isError: true);
    } else {
      setState(() => _tab = 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = context.select<DriverController, int>((c) => c.pending.length);
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const DriverMissionTab(),
          DriverHistoryTab(visible: _tab == 1),
          const DriverAccountTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.emergency_outlined),
            ),
            selectedIcon: const Icon(Icons.emergency),
            label: 'Nhiệm vụ',
          ),
          const NavigationDestination(
            icon: Icon(Icons.history),
            label: 'Lịch sử',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Tài khoản',
          ),
        ],
      ),
    );
  }
}
