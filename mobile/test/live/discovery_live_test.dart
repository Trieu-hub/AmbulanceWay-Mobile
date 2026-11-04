// Quét mạng thật tìm backend, cần backend đang chạy bằng profile "lan" trên máy này:
//   dotnet run --launch-profile lan
//   flutter test test/live/discovery_live_test.dart
import 'package:ambulance_way/services/server_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('địa chỉ cũ không còn dùng được: quét Wi-Fi tìm ra backend', () async {
    final watch = Stopwatch()..start();
    final found = await const ServerDiscovery().find(current: 'http://10.12.8.59:5199');
    // ignore: avoid_print
    print('Tìm thấy: $found sau ${watch.elapsedMilliseconds} ms');
    expect(found, matches(RegExp(r'^http://\d+\.\d+\.\d+\.\d+:5199$')));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
