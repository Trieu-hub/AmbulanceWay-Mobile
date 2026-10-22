import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/geo.dart';
import '../../services/location_service.dart';
import '../../widgets/app_map.dart';
import '../../widgets/common.dart';

/// Chọn vị trí cấp cứu bằng cách kéo bản đồ sao cho ghim đỏ nằm đúng chỗ.
/// Đóng màn hình và trả về tọa độ đã chọn.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.initial});

  final LatLng initial;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final MapController _map = MapController();
  late LatLng _center = widget.initial;
  bool _locating = false;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  Future<void> _goToMyLocation() async {
    setState(() => _locating = true);
    final position = await LocationService().current();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) {
      showAppSnack(context, 'Không lấy được vị trí GPS. Hãy kéo bản đồ để chọn.', isError: true);
      return;
    }
    _map.move(position, 17);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chọn vị trí cấp cứu')),
      body: Stack(
        children: [
          AppMap(
            controller: _map,
            center: widget.initial,
            zoom: 16,
            onMoved: (center) => setState(() => _center = center),
          ),
          // Ghim cố định giữa màn hình; mũi ghim chỉ đúng tâm bản đồ.
          const IgnorePointer(
            child: Center(
              child: Padding(
                padding: EdgeInsets.only(bottom: 44),
                child: Icon(Icons.location_on, size: 48, color: MapColors.patient),
              ),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: FloatingActionButton.small(
              heroTag: 'picker-locate',
              tooltip: 'Vị trí của tôi',
              onPressed: _locating ? null : _goToMyLocation,
              child: _locating
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Kéo bản đồ để ghim đỏ nằm đúng nơi cần xe đến\n${formatCoordinates(_center)}',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              PrimaryButton(
                label: 'DÙNG VỊ TRÍ NÀY',
                icon: Icons.check,
                onPressed: () => Navigator.of(context).pop(_center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
