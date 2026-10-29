import 'api_client.dart';
import 'app_config.dart';
import 'device_info.dart';

/// Phát hiện những địa chỉ máy chủ chắc chắn không dùng được trên thiết bị đang chạy app,
/// để báo cho người dùng biết phải nhập gì thay vì chỉ báo "không kết nối được".
class ServerAddress {
  ServerAddress._();

  /// Địa chỉ của máy tính (máy chủ) khi nhìn từ máy ảo Android.
  static const String androidEmulatorHost = '10.0.2.2';

  static const int _port = AppConfig.backendPort;
  static const String _example = 'http://192.168.1.10:$_port';
  static const String _localhostUrl = 'http://localhost:$_port';
  static const String _emulatorUrl = 'http://$androidEmulatorHost:$_port';

  static const String _useLanIp =
      'Hãy nhập IP Wi-Fi của máy tính chạy backend (xem bằng lệnh ipconfig), ví dụ $_example.';

  static final RegExp _ipv4 = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');

  /// localhost, 127.x.x.x, ::1
  static bool isLoopback(String host) {
    final h = host.toLowerCase();
    return h == 'localhost' || h == '::1' || h == '[::1]' || h.startsWith('127.');
  }

  /// Câu giải thích (tiếng Việt) khi [baseUrl] không dùng được trên [device]; null nếu không thấy vấn đề.
  static String? problem(String baseUrl, [DeviceInfo? device]) {
    final d = device ?? DeviceInfo.current;
    final url = ApiClient.normalizeBaseUrl(baseUrl);
    if (url.isEmpty) return 'Chưa nhập địa chỉ máy chủ. Ví dụ: $_example.';

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      return 'Địa chỉ máy chủ không hợp lệ. Ví dụ đúng: $_example.';
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return 'Địa chỉ máy chủ phải bắt đầu bằng http://, ví dụ $_example.';
    }

    final host = uri.host.toLowerCase();
    if (RegExp(r'^\d+(,\d+)+$').hasMatch(host)) {
      return 'IP phải ngăn cách bằng dấu chấm, không phải dấu phẩy. Ví dụ: $_example.';
    }
    if (host == '0.0.0.0' || host == '::') {
      return '$host chỉ là cách backend báo "đang nghe trên mọi mạng", không dùng để kết nối. '
          '${_whatToUse(d)}';
    }
    if (isLoopback(host)) {
      final issue = _loopbackIssue(d);
      if (issue != null) return issue;
    }
    if (host == androidEmulatorHost) {
      final issue = _emulatorHostIssue(d);
      if (issue != null) return issue;
    }

    // Backend chạy thử chỉ có HTTP ở cổng 5199 (HTTPS của profile "https" nằm ở cổng khác).
    if (uri.scheme == 'https' && uri.port == _port) {
      return 'Cổng $_port của backend dùng http://, không phải https://. '
          'Hãy nhập http://${uri.host}:$_port.';
    }
    final isLocalHost = _ipv4.hasMatch(host) || isLoopback(host);
    if (!uri.hasPort && isLocalHost) {
      return 'Thiếu cổng của backend. Hãy nhập ${uri.scheme}://${uri.host}:$_port.';
    }
    if ((uri.path.isNotEmpty && uri.path != '/') || uri.hasQuery || uri.hasFragment) {
      final origin = '${uri.scheme}://${uri.authority}';
      return 'Chỉ nhập địa chỉ gốc của máy chủ ($origin), bỏ phần "${uri.path}" phía sau.';
    }
    return null;
  }

  /// Gợi ý khi không kết nối được mà địa chỉ trông vẫn hợp lệ.
  static String connectionAdvice([DeviceInfo? device]) {
    final d = device ?? DeviceInfo.current;
    if (d.maybePhysicalPhone) {
      return 'Kiểm tra: điện thoại và máy tính cùng một mạng Wi-Fi, backend chạy bằng '
          '"dotnet run --launch-profile lan", tường lửa Windows cho phép cổng $_port, '
          'và IP trong Cài đặt máy chủ đúng với IP hiện tại của máy tính.';
    }
    return 'Kiểm tra backend đã bật và địa chỉ trong Cài đặt máy chủ.';
  }

  static String? _loopbackIssue(DeviceInfo d) {
    if (d.isWeb) {
      final page = d.pageHost;
      if (page == null || page.isEmpty || isLoopback(page)) return null;
      return 'Trang này đang được mở qua địa chỉ $page, nên "localhost" là chính thiết bị đang mở '
          'trang chứ không phải máy tính chạy backend. $_useLanIp';
    }
    if (d.isAndroid) {
      if (d.isEmulator == true) {
        return 'Trong máy ảo Android, "localhost" là chính máy ảo chứ không phải máy tính. '
            'Hãy dùng $_emulatorUrl.';
      }
      return 'Trên điện thoại, "localhost" là chính điện thoại chứ không phải máy tính chạy '
          'backend. $_useLanIp'
          '${d.isEmulator == null ? ' (Riêng máy ảo Android thì dùng $_emulatorUrl.)' : ''}';
    }
    if (d.isIOS && d.isEmulator != true) {
      return 'Trên iPhone/iPad, "localhost" là chính thiết bị chứ không phải máy tính chạy '
          'backend. $_useLanIp';
    }
    // Máy tính, iOS Simulator: localhost đúng là máy đang chạy backend.
    return null;
  }

  static String? _emulatorHostIssue(DeviceInfo d) {
    if (d.isAndroid && d.isEmulator == true) return null;
    if (d.isAndroid && d.isEmulator == null) {
      return 'Nếu đây là điện thoại thật thì $androidEmulatorHost không dùng được '
          '(địa chỉ này chỉ dành cho máy ảo Android). $_useLanIp';
    }
    return '$androidEmulatorHost chỉ dùng được trong máy ảo Android. ${_whatToUse(d)}';
  }

  static String _whatToUse(DeviceInfo d) {
    if (d.isAndroid && d.isEmulator == true) return 'Trong máy ảo Android hãy dùng $_emulatorUrl.';
    if (d.maybePhysicalPhone) return _useLanIp;
    return 'Nếu backend chạy trên chính máy này hãy dùng $_localhostUrl, '
        'nếu không thì nhập IP của máy tính chạy backend, ví dụ $_example.';
  }
}
