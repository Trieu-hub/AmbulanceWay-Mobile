import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../models/session.dart';

/// Trạng thái dùng chung toàn app: địa chỉ máy chủ và phiên đăng nhập.
class AppState extends ChangeNotifier {
  AppState({ApiClient? api})
      : api = api ?? ApiClient(baseUrl: AppConfig.defaultBaseUrl) {
    this.api.onSessionRejected = _handleSessionRejected;
  }

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

    _ready = true;
    notifyListeners();
  }

  Future<void> setBaseUrl(String url) async {
    api.baseUrl = url;
    await _prefs?.setString(_keyServerUrl, api.baseUrl);
    notifyListeners();
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
