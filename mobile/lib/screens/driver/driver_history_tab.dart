import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_client.dart';
import '../../core/geo.dart';
import '../../models/driver_models.dart';
import '../../services/driver_api.dart';
import '../../state/app_state.dart';
import '../../widgets/common.dart';

/// Tab "Lịch sử": các chuyến tài xế này đã hoàn thành.
class DriverHistoryTab extends StatefulWidget {
  const DriverHistoryTab({super.key, required this.visible});

  /// Tab đang được chọn; mỗi lần chuyển sang tab này thì tải lại dữ liệu.
  final bool visible;

  @override
  State<DriverHistoryTab> createState() => _DriverHistoryTabState();
}

class _DriverHistoryTabState extends State<DriverHistoryTab> {
  TripPage? _page;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.visible) _load();
  }

  @override
  void didUpdateWidget(DriverHistoryTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible && !oldWidget.visible) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await DriverApi(context.read<AppState>().api).trips();
      if (mounted) setState(() => _page = page);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lịch sử chuyến')),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final page = _page;
    if (page == null) {
      if (_error != null) return ErrorRetry(message: _error!, onRetry: _load);
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(child: _StatCard(value: '${page.total}', label: 'Chuyến đã chạy')),
              const SizedBox(width: 12),
              Expanded(
                child: _StatCard(
                  value: formatDistance(page.totalDistanceKm),
                  label: 'Tổng quãng đường',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (page.trips.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 56),
              child: Column(
                children: [
                  Icon(Icons.route, size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  const Text('Chưa có chuyến nào được ghi nhận.'),
                  const SizedBox(height: 4),
                  Text('Chuyến hoàn thành sẽ hiện ở đây.',
                      style: TextStyle(color: Theme.of(context).hintColor)),
                ],
              ),
            )
          else
            for (final trip in page.trips) _TripCard(trip: trip),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: theme.textTheme.headlineSmall?.copyWith(
                    color: theme.colorScheme.primary, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(color: theme.hintColor)),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.trip});

  final TripRecord trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final finished = trip.completedAt ?? trip.createdAt;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.personal_injury, size: 18, color: Color(0xFFD32F2F)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(trip.patientAddress)),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.local_hospital, size: 18, color: Color(0xFF2E7D32)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(trip.hospitalName,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const Divider(height: 20),
              Row(
                children: [
                  Text(formatDistance(trip.distanceKm)),
                  const Text('  •  '),
                  Text(formatMinutes(trip.durationMinutes)),
                  const Spacer(),
                  if (finished != null)
                    Text(formatDateTime(finished), style: TextStyle(color: theme.hintColor)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
