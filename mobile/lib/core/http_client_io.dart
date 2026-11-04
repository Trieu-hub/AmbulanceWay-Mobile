import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Giới hạn riêng thời gian mở kết nối: máy chủ trong mạng nội bộ trả lời trong vài mili giây,
/// còn địa chỉ cũ (IP máy tính đã đổi) thì không ai trả lời. Không đợi đủ 15 giây mới báo lỗi.
http.Client createHttpClient() =>
    IOClient(HttpClient()..connectionTimeout = const Duration(seconds: 5));
