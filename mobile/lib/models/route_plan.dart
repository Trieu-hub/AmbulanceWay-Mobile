import 'package:latlong2/latlong.dart';

/// Một chỉ dẫn trên lộ trình ("Rẽ trái vào Lý Thường Kiệt").
class RouteStep {
  const RouteStep({required this.instruction, required this.distanceMeters});

  final String instruction;
  final double distanceMeters;
}

/// Lộ trình giữa hai điểm.
class RoutePlan {
  const RoutePlan({
    required this.points,
    required this.distanceKm,
    required this.durationMinutes,
    this.steps = const [],
    this.isEstimate = false,
  });

  final List<LatLng> points;
  final double distanceKm;
  final int durationMinutes;
  final List<RouteStep> steps;

  /// true khi không gọi được dịch vụ dẫn đường và chỉ ước lượng theo đường thẳng.
  final bool isEstimate;

  LatLng get origin => points.first;
  LatLng get destination => points.last;
}
