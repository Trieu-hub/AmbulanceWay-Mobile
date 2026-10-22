import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/json_reader.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

/// Nhập địa chỉ backend ASP.NET mà app sẽ kết nối.
class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final TextEditingController _url;
  bool _testing = false;
  String? _result;
  bool _resultOk = false;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().baseUrl);
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  /// Gọi GET /api/mobile/ping tới địa chỉ đang nhập (chưa lưu).
  Future<bool> _test() async {
    setState(() {
      _testing = true;
      _result = null;
    });
    final probe = ApiClient(baseUrl: _url.text);
    try {
      final data = JsonReader.tryFrom(await probe.get('/api/mobile/ping'));
      final ok = data?.boolean('ok') ?? false;
      _resultOk = ok;
      _result = ok
          ? 'Kết nối thành công tới ${probe.baseUrl}'
          : 'Địa chỉ này không phải máy chủ AmbulanceWay.';
    } on ApiException catch (error) {
      _resultOk = false;
      _result = error.statusCode == 404
          ? 'Máy chủ này chưa có API cho app (thiếu /api/mobile/ping).'
          : error.message;
    } finally {
      probe.close();
    }
    if (mounted) setState(() => _testing = false);
    return _resultOk;
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    await app.setBaseUrl(_url.text);
    if (!mounted) return;
    showAppSnack(context, 'Đã lưu địa chỉ máy chủ.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Cài đặt máy chủ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Địa chỉ máy chủ',
              hintText: 'http://192.168.1.10:5199',
              prefixIcon: Icon(Icons.dns),
            ),
          ),
          const SizedBox(height: 12),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Icon(
                    _resultOk ? Icons.check_circle : Icons.error,
                    color: _resultOk ? Colors.green : theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_result!)),
                ],
              ),
            ),
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: _testing
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.wifi_tethering),
            label: const Text('Kiểm tra kết nối'),
          ),
          const SizedBox(height: 12),
          PrimaryButton(label: 'Lưu', icon: Icons.save, onPressed: _save),
          const SizedBox(height: 28),
          Text('Nhập địa chỉ nào?', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const _Hint(
            title: 'Chạy app trên chính máy tính đang bật backend (Chrome, Windows)',
            value: 'http://localhost:5199',
          ),
          const _Hint(
            title: 'Máy ảo Android',
            value: 'http://10.0.2.2:5199',
          ),
          const _Hint(
            title: 'Điện thoại thật cùng mạng Wi-Fi',
            value: 'http://<IP của máy tính>:5199',
            note: 'Chạy backend bằng: dotnet run --launch-profile lan',
          ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.title, required this.value, this.note});

  final String title;
  final String value;
  final String? note;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600)),
          if (note != null)
            Text(note!, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
        ],
      ),
    );
  }
}
