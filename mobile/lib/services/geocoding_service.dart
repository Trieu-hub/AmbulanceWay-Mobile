import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../core/app_config.dart';
import '../core/json_reader.dart';

/// Đổi tọa độ thành địa chỉ bằng Nominatim (OpenStreetMap) để bệnh nhân
/// không phải gõ địa chỉ trong lúc khẩn cấp.
class GeocodingService {
  GeocodingService({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// Trả về null nếu không tra được (mất mạng, quá 6 giây...).
  Future<String?> reverse(LatLng point) async {
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'zoom': '18',
        'accept-language': 'vi',
      });
      final response = await _http.get(uri, headers: {
        // Trình duyệt không cho đặt User-Agent; các nền tảng khác phải khai báo theo quy định của OSM.
        if (!kIsWeb) 'User-Agent': AppConfig.userAgentPackage,
      }).timeout(const Duration(seconds: 6));
      if (response.statusCode != 200) return null;
      return shortAddress(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Exception {
      return null;
    }
  }

  // Mã bưu chính Việt Nam gồm 5-6 chữ số; số nhà ngắn hơn nên không bị nhầm.
  static final RegExp _postalCode = RegExp(r'^\d{5,6}$');

  /// Rút gọn `display_name` của Nominatim: bỏ mã bưu chính và tên nước.
  static String? shortAddress(Object? body) {
    final name = JsonReader.tryFrom(body)?.stringOrNull('display_name');
    if (name == null) return null;
    final parts = name
        .split(',')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty && part != 'Việt Nam' && !_postalCode.hasMatch(part))
        .toList();
    if (parts.isEmpty) return null;
    return parts.take(5).join(', ');
  }
}
