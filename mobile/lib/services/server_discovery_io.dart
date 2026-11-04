import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Gọi GET /api/mobile/ping, true nếu đúng là backend AmbulanceWay.
Future<bool> pingServer(String baseUrl, {Duration timeout = const Duration(seconds: 2)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final request = await client.getUrl(Uri.parse('$baseUrl/api/mobile/ping')).timeout(timeout);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) return false;
    final body = await response.transform(utf8.decoder).join().timeout(timeout);
    final data = jsonDecode(body);
    return data is Map && data['ok'] == true && data['app'] == 'AmbulanceWay';
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Quét các mạng Wi-Fi / điểm phát mà thiết bị đang nối (mỗi mạng coi như x.y.z.1-254)
/// tìm máy đang chạy backend ở [port]. Trả về địa chỉ gốc, ví dụ "http://192.168.1.10:5199".
Future<String?> scanLocalNetwork(int port) async {
  final subnets = <String>{};
  try {
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final nic in interfaces) {
      // Bỏ mạng di động (rmnet, ccmni), VPN (tun, ppp): máy tính chạy backend không nằm ở đó.
      if (RegExp(r'^(rmnet|ccmni|tun|ppp|dummy|lo)').hasMatch(nic.name)) continue;
      for (final address in nic.addresses) {
        if (address.isLoopback || !_isPrivate(address.address)) continue;
        final parts = address.address.split('.');
        subnets.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }
  } on Object {
    return null;
  }
  if (subnets.isEmpty) return null;

  final hosts = <String>[
    for (final subnet in subnets.take(3))
      for (var i = 1; i <= 254; i++) '$subnet.$i',
  ];

  // Bước 1: máy nào mở cổng [port] (máy không tồn tại thì hết giờ, máy không chạy backend thì từ chối ngay).
  final open = <String>[];
  const batch = 128;
  for (var start = 0; start < hosts.length; start += batch) {
    final slice = hosts.sublist(start, start + batch > hosts.length ? hosts.length : start + batch);
    await Future.wait(
      slice.map((host) async {
        try {
          final socket = await Socket.connect(
            host,
            port,
            timeout: const Duration(milliseconds: 1200),
          );
          socket.destroy();
          open.add(host);
        } on Object {
          // Không có máy chủ ở địa chỉ này.
        }
      }),
    );
    // Bước 2: xác nhận đúng là AmbulanceWay rồi dừng ngay, khỏi quét tiếp.
    for (final host in open) {
      final url = 'http://$host:$port';
      if (await pingServer(url)) return url;
    }
    open.clear();
  }
  return null;
}

bool _isPrivate(String ip) {
  final p = ip.split('.').map(int.tryParse).toList();
  if (p.length != 4 || p.contains(null)) return false;
  final a = p[0]!, b = p[1]!;
  return a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
}
