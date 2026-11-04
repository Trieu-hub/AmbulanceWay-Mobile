import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../models/session.dart';
import '../services/server_discovery.dart';

/// Trạng thái dùng chung toàn app: địa chỉ máy chủ và phiên đăng nhập.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api, this._discovery})
      : api = api ?? ApiClient(baseUrl: AppConfig.defaultBaseUrl) {
    this.api.onSessionRejected = _handleSessionRejected;
    this.api.onUnreachable = rediscoverServer;
  }

  /// null: không tự tìm máy chủ (bản web, máy tính, test không truyền vào).
  final ServerDiscovery? _discovery;
  Future<String?>? _discovering;
  DateTime? _lastFailedDiscovery;

  /// Thiết bị này có tự tìm máy chủ trong mạng Wi-Fi được không (điện thoại, máy ảo).
  bool get canDiscover => _discovery != null;

  /// true khi đang tự tìm máy chủ trong mạng (để màn hình hiện trạng thái).
  bool get discovering => _discovering != null;

  static const String _keyServerUrl = 'server_url';
  static const String _keySession = 'session';
  static const String _keySkippedRating = 'skipped_rating_case';

  final ApiClient api;

  SharedPreferences? _prefs;
  AppSession? _session;
  bool _ready = false;
  String? _notice;

  /// false cho tới khi đọc xong dữ liệu đã lưu trên máy.
  bool get ready => _ready;

  AppSession? get session => _session;

  String get baseUrl => api.baseUrl;

  /// Thông báo một lần cho màn hình chào (ví dụ "phiên đăng nhập đã hết hạn").
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefs = prefs;

    final savedUrl = prefs.getString(_keyServerUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) api.baseUrl = savedUrl;

    final savedSession = prefs.getString(_keySession);
    if (savedSession != null) {
      try {
        _session = AppSession.fromJson(jsonDecode(savedSession));
      } on FormatException {
        _session = null;
      }
    }
    api.token = _session?.token;

    // Mở app sau khi đổi Wi-Fi: IP máy tính có thể đã khác, kiểm tra và tự sửa địa chỉ ngay.
    if (_discovery != null) unawaited(rediscoverServer());

    _ready = true;
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    api.baseUrl = url;
    await _prefs?.setString(_keyServerUrl, api.baseUrl);
    notifyListeners();
  }

  /// Máy chủ không trả lời ở địa chỉ đang lưu (thường do IP máy tính đổi khi đổi Wi-Fi):
  /// tìm lại trong mạng nội bộ và lưu địa chỉ mới. Trả về địa chỉ dùng được, null nếu không thấy.
  ///
  /// [force]: người dùng tự bấm "Tự tìm máy chủ", bỏ qua giới hạn số lần quét.
  Future<String?> rediscoverServer({bool force = false}) {
    final discovery = _discovery;
    if (discovery == null) return Future.value(null);
    final running = _discovering;
    if (running != null) return running;
    // Máy chủ tắt hẳn thì mọi request đều lỗi: không quét lại mạng liên tục.
    final lastFailed = _lastFailedDiscovery;
    if (!force &&
        lastFailed != null &&
        DateTime.now().difference(lastFailed) < const Duration(seconds: 30)) {
      return Future.value(null);
    }

    final future = _runDiscovery(discovery);
    _discovering = future;
    notifyListeners();
    return future;
  }

  Future<String?> _runDiscovery(ServerDiscovery discovery) async {
    try {
      final found = await discovery.find(current: api.baseUrl);
      if (found == null) {
        _lastFailedDiscovery = DateTime.now();
      } else {
        _lastFailedDiscovery = null;
        if (found != api.baseUrl) await setBaseUrl(found);
      }
      return found;
    } finally {
      _discovering = null;
      notifyListeners();
    }
  }

  Future<void> signIn(AppSession session) async {
    _session = session;
    api.token = session.token;
    await _prefs?.setString(_keySession, jsonEncode(session.toJson()));
    notifyListeners();
  }

  Future<void> signOut({String? notice}) async {
    if (_session == null) return;
    _session = null;
    _notice = notice;
    api.token = null;
    await _prefs?.remove(_keySession);
    notifyListeners();
  }

  void _handleSessionRejected() {
    signOut(notice: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.');
  }

  /// Ca mà bệnh nhân đã bấm "Bỏ qua" đánh giá, để không hỏi lại ở lần mở app sau.
  int? get skippedRatingCaseId => _prefs?.getInt(_keySkippedRating);

  Future<void> rememberSkippedRating(int caseId) async {
    await _prefs?.setInt(_keySkippedRating, caseId);
  }
}
