import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/geo.dart';
import '../core/json_reader.dart';
import '../models/route_plan.dart';

/// Tìm đường bằng máy chủ OSRM công cộng - cùng dịch vụ mà bản web dùng
/// qua leaflet-routing-machine.
class RoutingService {
  RoutingService({http.Client? httpClient, this.host = 'router.project-osrm.org'})
      : _http = httpClient ?? http.Client();

  final http.Client _http;
  final String host;

  static const Duration _timeout = Duration(seconds: 10);

  /// Luôn trả về một lộ trình: nếu OSRM lỗi thì ước lượng theo đường thẳng
  /// để tài xế vẫn thấy hướng đi và khoảng cách.
  Future<RoutePlan> route(LatLng from, LatLng to) async {
    try {
      final uri = Uri.https(
        host,
        '/route/v1/driving/${from.longitude},${from.latitude};${to.longitude},${to.latitude}',
        {'overview': 'full', 'geometries': 'geojson', 'steps': 'true'},
      );
      final response = await _http.get(uri).timeout(_timeout);
      if (response.statusCode == 200) {
        final plan = parseOsrm(jsonDecode(utf8.decode(response.bodyBytes)));
        if (plan != null) return plan;
      }
    } on Exception {
      // Mất mạng, quá thời gian hoặc JSON hỏng: dùng ước lượng bên dưới.
    }
    return straightLine(from, to);
  }

  /// Ước lượng khi không có dữ liệu đường: đường thẳng nhân hệ số quanh co 1,3.
  static RoutePlan straightLine(LatLng from, LatLng to) {
    final distanceKm = haversineKm(from, to) * 1.3;
    return RoutePlan(
      points: [from, to],
      distanceKm: distanceKm,
      durationMinutes: estimateMinutes(distanceKm),
      isEstimate: true,
    );
  }

  /// Đọc phản hồi của OSRM `/route/v1`. Trả về null nếu không có tuyến nào.
  static RoutePlan? parseOsrm(Object? body) {
    final root = JsonReader.tryFrom(body);
    if (root == null || root.string('code') != 'Ok') return null;

    final routes = root.objects('routes');
    if (routes.isEmpty) return null;
    final route = routes.first;

    final coordinates = route.object('geometry')?.raw('coordinates');
    if (coordinates is! List) return null;
    final points = <LatLng>[
      for (final pair in coordinates)
        // GeoJSON ghi [kinh độ, vĩ độ].
        if (pair is List && pair.length >= 2 && pair[0] is num && pair[1] is num)
          LatLng((pair[1] as num).toDouble(), (pair[0] as num).toDouble()),
    ];
    if (points.length < 2) return null;

    final steps = <RouteStep>[
      for (final leg in route.objects('legs'))
        for (final step in leg.objects('steps'))
          RouteStep(
            instruction: describeStep(step),
            distanceMeters: step.number('distance'),
          ),
    ];

    final minutes = (route.number('duration') / 60).round();
    return RoutePlan(
      points: points,
      distanceKm: route.number('distance') / 1000,
      durationMinutes: minutes < 1 ? 1 : minutes,
      steps: steps,
    );
  }

  /// Dịch một bước của OSRM sang câu chỉ dẫn tiếng Việt.
  static String describeStep(JsonReader step) {
    final maneuver = step.object('maneuver');
    final type = maneuver?.string('type') ?? '';
    final modifier = maneuver?.string('modifier') ?? '';
    final road = step.string('name');
    final onto = road.isEmpty ? '' : ' vào $road';

    switch (type) {
      case 'depart':
        return road.isEmpty ? 'Xuất phát' : 'Xuất phát trên $road';
      case 'arrive':
        return 'Đến nơi';
      case 'roundabout':
      case 'rotary':
        return 'Vào vòng xuyến$onto';
      case 'merge':
        return 'Nhập làn$onto';
      case 'on ramp':
        return 'Vào đường dẫn$onto';
      case 'off ramp':
        return 'Ra khỏi đường chính$onto';
    }

    switch (modifier) {
      case 'left':
        return 'Rẽ trái$onto';
      case 'right':
        return 'Rẽ phải$onto';
      case 'slight left':
        return 'Chếch sang trái$onto';
      case 'slight right':
        return 'Chếch sang phải$onto';
      case 'sharp left':
        return 'Rẽ gắt sang trái$onto';
      case 'sharp right':
        return 'Rẽ gắt sang phải$onto';
      case 'uturn':
        return 'Quay đầu$onto';
      default:
        return road.isEmpty ? 'Đi thẳng' : 'Đi thẳng trên $road';
    }
  }
}
