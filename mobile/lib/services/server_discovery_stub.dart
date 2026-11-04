/// Bản web không mở socket được nên không tự tìm máy chủ.
Future<bool> pingServer(String baseUrl, {Duration timeout = const Duration(seconds: 2)}) async =>
    false;

Future<String?> scanLocalNetwork(int port) async => null;
