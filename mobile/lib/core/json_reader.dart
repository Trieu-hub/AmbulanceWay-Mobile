/// Đọc JSON không phân biệt hoa thường ở tên trường.
///
/// Backend đặt tên trường không thống nhất: có nơi PascalCase (`CaseId`), có nơi
/// camelCase (`caseId`), cả ở REST lẫn SignalR. App vì thế không dựa vào kiểu chữ.
class JsonReader {
  JsonReader(Map<dynamic, dynamic>? source)
      : _values = {
          for (final entry in (source ?? const {}).entries)
            entry.key.toString().toLowerCase(): entry.value,
        };

  final Map<String, dynamic> _values;

  /// Trả về null nếu [value] không phải object JSON.
  static JsonReader? tryFrom(Object? value) =>
      value is Map ? JsonReader(value) : null;

  /// Danh sách object JSON; phần tử không phải object bị bỏ qua.
  static List<JsonReader> listFrom(Object? value) => value is List
      ? value.whereType<Map>().map(JsonReader.new).toList()
      : const [];

  Object? raw(String key) => _values[key.toLowerCase()];

  bool has(String key) => raw(key) != null;

  String? stringOrNull(String key) {
    final value = raw(key);
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  String string(String key, [String fallback = '']) =>
      stringOrNull(key) ?? fallback;

  int? intOrNull(String key) {
    final value = raw(key);
    if (value is int) return value;
    if (value is num) return value.round();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  int integer(String key, [int fallback = 0]) => intOrNull(key) ?? fallback;

  double? doubleOrNull(String key) {
    final value = raw(key);
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
    return null;
  }

  double number(String key, [double fallback = 0]) =>
      doubleOrNull(key) ?? fallback;

  bool boolean(String key, [bool fallback = false]) {
    final value = raw(key);
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() == 'true';
    return fallback;
  }

  /// Thời điểm do máy chủ ghi (luôn là UTC), đổi sang giờ của máy.
  DateTime? serverTime(String key) => parseServerTime(stringOrNull(key));

  /// Ngày không kèm múi giờ (ví dụ ngày sinh).
  DateTime? date(String key) {
    final text = stringOrNull(key);
    return text == null ? null : DateTime.tryParse(text);
  }

  JsonReader? object(String key) => tryFrom(raw(key));

  List<JsonReader> objects(String key) => listFrom(raw(key));
}

final RegExp _hasTimeZone = RegExp(r'(z|[+-]\d{2}:?\d{2})$', caseSensitive: false);

/// Backend lưu DateTime.UtcNow nhưng nhiều API trả về thiếu hậu tố "Z";
/// coi mọi thời điểm không ghi múi giờ là UTC rồi đổi sang giờ địa phương.
DateTime? parseServerTime(String? text) {
  if (text == null || text.isEmpty) return null;
  final normalized = _hasTimeZone.hasMatch(text) ? text : '${text}Z';
  return DateTime.tryParse(normalized)?.toLocal();
}
