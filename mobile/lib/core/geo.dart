import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Khoảng cách đường chim bay (km) theo công thức Haversine - cùng công thức với SosController.
double haversineKm(LatLng a, LatLng b) {
  const earthRadiusKm = 6371.0;
  final dLat = _toRadians(b.latitude - a.latitude);
  final dLng = _toRadians(b.longitude - a.longitude);
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(_toRadians(a.latitude)) *
          math.cos(_toRadians(b.latitude)) *
          math.sin(dLng / 2) *
          math.sin(dLng / 2);
  return earthRadiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _toRadians(double degrees) => degrees * math.pi / 180.0;

/// Ước lượng số phút di chuyển với tốc độ trung bình 25 km/h (giống backend).
int estimateMinutes(double distanceKm) {
  final minutes = (distanceKm / 25.0 * 60).ceil();
  return minutes < 1 ? 1 : minutes;
}

String formatDistance(double km) {
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
}

String formatMeters(double meters) =>
    meters < 1000 ? '${meters.round()} m' : formatDistance(meters / 1000);

String formatMinutes(int minutes) {
  if (minutes < 60) return '$minutes phút';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours giờ' : '$hours giờ $rest phút';
}

String _two(int value) => value.toString().padLeft(2, '0');

String formatTime(DateTime time) => '${_two(time.hour)}:${_two(time.minute)}';

String formatDate(DateTime time) =>
    '${_two(time.day)}/${_two(time.month)}/${time.year}';

String formatDateTime(DateTime time) => '${formatTime(time)} ${formatDate(time)}';

String formatCoordinates(LatLng point) =>
    '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
