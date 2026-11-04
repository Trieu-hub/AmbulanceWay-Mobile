import '../core/api_client.dart';
import '../core/app_config.dart';
import 'server_discovery_stub.dart' if (dart.library.io) 'server_discovery_io.dart' as impl;

/// Tự tìm backend trong mạng Wi-Fi đang dùng.
///
/// Dùng khi IP của máy tính chạy backend đổi (đổi Wi-Fi, bật lại điểm phát): app vẫn giữ
/// địa chỉ cũ nên báo "Máy chủ không phản hồi" dù điện thoại và máy tính cùng mạng.
class ServerDiscovery {
  const ServerDiscovery();

  /// Địa chỉ máy chủ đang dùng được: [current] nếu vẫn trả lời, không thì máy chủ tìm thấy
  /// trong mạng nội bộ. null nếu không thấy máy chủ nào.
  Future<String?> find({String? current}) async {
    if (current != null && current.isNotEmpty) {
      final url = ApiClient.normalizeBaseUrl(current);
      if (await impl.pingServer(url)) return url;
    }
    return impl.scanLocalNetwork(AppConfig.backendPort);
  }
}
