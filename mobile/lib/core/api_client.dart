import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Lỗi khi gọi API, [message] đã là câu tiếng Việt hiển thị được cho người dùng.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});

  final String message;

  /// null nghĩa là không kết nối được tới máy chủ.
  final int? statusCode;

  bool get isNetworkError => statusCode == null;

  @override
  String toString() => message;
}

/// Lớp gọi REST API của backend AmbulanceWay.
class ApiClient {
  ApiClient({required String baseUrl, http.Client? httpClient})
      : _baseUrl = normalizeBaseUrl(baseUrl),
        _http = httpClient ?? http.Client();

  static const Duration timeout = Duration(seconds: 15);

  final http.Client _http;
  String _baseUrl;

  /// JWT của phiên đăng nhập hiện tại (null khi chưa đăng nhập).
  String? token;

  /// Được gọi khi máy chủ từ chối token (hết hạn, tài khoản bị khóa).
  void Function()? onSessionRejected;

  String get baseUrl => _baseUrl;

  set baseUrl(String value) => _baseUrl = normalizeBaseUrl(value);

  /// "192.168.1.10:5199/" -> "http://192.168.1.10:5199"
  static String normalizeBaseUrl(String input) {
    var url = input.trim();
    if (url.isEmpty) return url;
    if (!url.contains('://')) url = 'http://$url';
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final uri = Uri.parse('$_baseUrl$path');
    return query == null ? uri : uri.replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = false}) => {
        'Accept': 'application/json',
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, {Object? body}) => _send(() => _http.post(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body ?? const <String, dynamic>{}),
      ));

  Future<dynamic> put(String path, {Object? body}) => _send(() => _http.put(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(body ?? const <String, dynamic>{}),
      ));

  /// Gửi form (application/x-www-form-urlencoded) cho các action MVC của bản web.
  Future<dynamic> postForm(String path, Map<String, String> fields) =>
      _send(() => _http.post(
            _uri(path),
            headers: {
              'Accept': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: fields,
          ));

  Future<dynamic> _send(Future<http.Response> Function() request) async {
    final sentToken = token;
    http.Response response;
    try {
      response = await request().timeout(timeout);
    } on TimeoutException {
      throw ApiException('Máy chủ không phản hồi ($_baseUrl). Vui lòng thử lại.');
    } on http.ClientException {
      throw ApiException(
          'Không kết nối được máy chủ ($_baseUrl). Kiểm tra mạng và địa chỉ máy chủ.');
    } on FormatException {
      throw ApiException('Địa chỉ máy chủ không hợp lệ ($_baseUrl).');
    } on ArgumentError {
      throw ApiException('Địa chỉ máy chủ không hợp lệ ($_baseUrl).');
    }

    final data = _decode(response);
    if (response.statusCode >= 200 && response.statusCode < 300) return data;

    // Chỉ coi là hết phiên khi request có gửi token; đăng nhập sai mật khẩu cũng trả 401.
    if (response.statusCode == 401 && sentToken != null) {
      onSessionRejected?.call();
    }
    throw ApiException(
      errorMessage(data, response.statusCode),
      statusCode: response.statusCode,
    );
  }

  static dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    final text = utf8.decode(response.bodyBytes, allowMalformed: true);
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  /// Rút câu báo lỗi từ các dạng body mà backend trả về:
  /// `{message}`, `{Message}`, ProblemDetails `{title, errors}` hoặc chuỗi thuần.
  static String errorMessage(dynamic data, int statusCode) {
    if (data is Map) {
      for (final entry in data.entries) {
        final key = entry.key.toString().toLowerCase();
        if (key == 'message' && entry.value is String) {
          final text = (entry.value as String).trim();
          if (text.isNotEmpty) return text;
        }
      }
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
    }
    if (data is String) {
      final text = data.trim();
      // Trang lỗi HTML của ASP.NET không có ích với người dùng.
      if (text.isNotEmpty && text.length <= 200 && !text.startsWith('<')) {
        return text;
      }
    }
    switch (statusCode) {
      case 401:
        return 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.';
      case 403:
        return 'Bạn không có quyền thực hiện thao tác này.';
      case 404:
        return 'Không tìm thấy dữ liệu trên máy chủ.';
      default:
        return statusCode >= 500
            ? 'Máy chủ gặp lỗi ($statusCode). Vui lòng thử lại sau.'
            : 'Yêu cầu không hợp lệ ($statusCode).';
    }
  }

  void close() => _http.close();
}
