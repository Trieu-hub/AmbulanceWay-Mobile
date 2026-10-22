import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/app_config.dart';

/// Bản đồ OpenStreetMap dùng chung cho các màn hình.
class AppMap extends StatelessWidget {
  const AppMap({
    super.key,
    required this.center,
    this.zoom = 15,
    this.controller,
    this.markers = const [],
    this.polylines = const [],
    this.onTap,
    this.onLongPress,
    this.onMapReady,
    this.onMoved,
  });

  final LatLng center;
  final double zoom;
  final MapController? controller;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final ValueChanged<LatLng>? onTap;
  final ValueChanged<LatLng>? onLongPress;
  final VoidCallback? onMapReady;

  /// Gọi mỗi khi tâm bản đồ đổi (kéo, thu phóng).
  final ValueChanged<LatLng>? onMoved;

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        minZoom: 4,
        maxZoom: 19,
        // Tắt xoay bản đồ để hướng bắc luôn ở trên, dễ đọc khi đang lái xe.
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onTap: onTap == null ? null : (_, point) => onTap!(point),
        onLongPress: onLongPress == null ? null : (_, point) => onLongPress!(point),
        onMapReady: onMapReady,
        onPositionChanged:
            onMoved == null ? null : (camera, _) => onMoved!(camera.center),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: AppConfig.userAgentPackage,
          maxNativeZoom: 19,
        ),
        if (polylines.isNotEmpty) PolylineLayer(polylines: polylines),
        if (markers.isNotEmpty) MarkerLayer(markers: markers),
        const _Attribution(),
      ],
    );
  }
}

/// Dòng ghi nguồn bản đồ (bắt buộc theo giấy phép OpenStreetMap), thu gọn để không che bản đồ nhỏ.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomRight,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: const BoxDecoration(
          color: Color(0xCCFFFFFF),
          borderRadius: BorderRadius.only(topLeft: Radius.circular(6)),
        ),
        child: const Text(
          '© OpenStreetMap',
          style: TextStyle(fontSize: 10, color: Colors.black87),
        ),
      ),
    );
  }
}

/// Nội suy giữa hai tọa độ để ghim trên bản đồ trượt mượt thay vì nhảy cóc.
class LatLngTween extends Tween<LatLng> {
  LatLngTween({super.begin, super.end});

  @override
  LatLng lerp(double t) {
    final from = begin!;
    final to = end!;
    return LatLng(
      from.latitude + (to.latitude - from.latitude) * t,
      from.longitude + (to.longitude - from.longitude) * t,
    );
  }
}

/// Dựng lại [builder] với vị trí trượt dần tới [position] mỗi khi [position] đổi
/// (vị trí xe cập nhật 5 giây một lần nên cần chuyển động chuyển tiếp).
class SmoothPosition extends StatelessWidget {
  const SmoothPosition({super.key, required this.position, required this.builder});

  final LatLng position;
  final Widget Function(LatLng position) builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<LatLng>(
      tween: LatLngTween(begin: position, end: position),
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOut,
      builder: (_, value, _) => builder(value),
    );
  }
}

/// Ghim tròn có biểu tượng, dùng cho xe cấp cứu / bệnh nhân / bệnh viện.
Marker mapPin(
  LatLng point, {
  required IconData icon,
  required Color color,
  double size = 42,
}) {
  return Marker(
    point: point,
    width: size,
    height: size,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(0, 2)),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: size * 0.52),
    ),
  );
}

/// Màu dùng thống nhất trên bản đồ.
class MapColors {
  MapColors._();

  static const Color ambulance = Color(0xFF1565C0);
  static const Color patient = Color(0xFFD32F2F);
  static const Color hospital = Color(0xFF2E7D32);
  static const Color station = Color(0xFF6D4C41);
}
