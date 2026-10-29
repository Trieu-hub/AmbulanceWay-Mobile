import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/api_client.dart';
import '../core/device_info.dart';
import '../core/json_reader.dart';
import '../core/server_address.dart';
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

  /// Địa chỉ điện thoại nên nhập, do máy chủ gửi về khi kiểm tra kết nối.
  List<String> _lanUrls = const [];

  /// false: backend chỉ nghe trên localhost nên điện thoại thật không vào được (null: máy chủ không báo).
  bool? _phoneReachable;

  /// Vấn đề của địa chỉ đang nhập trên thiết bị này (cập nhật theo từng ký tự gõ).
  String? _problem;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: context.read<AppState>().baseUrl);
    _problem = ServerAddress.problem(_url.text);
    _url.addListener(_onUrlChanged);
  }

  @override
  void dispose() {
    _url.removeListener(_onUrlChanged);
    _url.dispose();
    super.dispose();
  }

  void _onUrlChanged() {
    final problem = ServerAddress.problem(_url.text);
    if (problem != _problem || _result != null) {
      setState(() {
        _problem = problem;
        _result = null;
      });
    }
  }

  void _fill(String value) {
    _url.text = value;
    _url.selection = TextSelection.collapsed(offset: value.length);
  }

  /// Gọi GET /api/mobile/ping tới địa chỉ đang nhập (chưa lưu).
  Future<bool> _test() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _testing = true;
      _result = null;
      _lanUrls = const [];
      _phoneReachable = null;
    });
    final probe = ApiClient(baseUrl: _url.text);
    try {
      final data = JsonReader.tryFrom(await probe.get('/api/mobile/ping'));
      final ok = data?.boolean('ok') ?? false;
      _resultOk = ok;
      _result = ok
          ? 'Kết nối thành công tới ${probe.baseUrl}'
          : 'Địa chỉ này không phải máy chủ AmbulanceWay.';
      final lan = data?.raw('lanUrls');
      if (ok && lan is List) _lanUrls = lan.whereType<String>().toList();
      _phoneReachable = data?.has('phoneReachable') == true ? data!.boolean('phoneReachable') : null;
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
    if (_url.text.trim().isEmpty) {
      showAppSnack(context, 'Nhập địa chỉ máy chủ trước khi lưu.', isError: true);
      return;
    }
    final problem = ServerAddress.problem(_url.text);
    if (problem != null) {
      final keep = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Địa chỉ này khó dùng được'),
          content: Text(problem),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Vẫn lưu'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Sửa lại'),
            ),
          ],
        ),
      );
      if (keep != true || !mounted) return;
    }
    final app = context.read<AppState>();
    await app.setBaseUrl(_url.text);
    if (!mounted) return;
    showAppSnack(context, 'Đã lưu địa chỉ máy chủ.');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final device = DeviceInfo.current;
    final phoneHint = _Hint(
      title: 'Điện thoại thật (cùng mạng Wi-Fi với máy tính)',
      value: 'http://<IP Wi-Fi của máy tính>:5199',
      note: 'Máy tính chạy backend bằng: dotnet run --launch-profile lan. '
          'Xem IP bằng lệnh ipconfig (dòng IPv4 Address). Không dùng localhost hay 0.0.0.0.',
      highlighted: device.maybePhysicalPhone,
    );
    final hints = <Widget>[
      _Hint(
        title: 'Chạy app trên chính máy tính đang bật backend (Chrome, Windows)',
        value: 'http://localhost:5199',
        onTap: _fill,
        highlighted: !device.isMobile,
      ),
      _Hint(
        title: 'Máy ảo Android',
        value: 'http://10.0.2.2:5199',
        onTap: _fill,
        highlighted: device.isAndroid && device.isEmulator == true,
      ),
    ];
    // Trên điện thoại, đưa gợi ý dành cho điện thoại thật lên đầu.
    if (device.maybePhysicalPhone) {
      hints.insert(0, phoneHint);
    } else {
      hints.add(phoneHint);
    }

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
          if (_problem != null && _url.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: WarningBox(message: _problem!),
            ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
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
          if (_resultOk && _result != null && _phoneReachable == false)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: WarningBox(
                message: 'Backend đang chỉ nhận kết nối từ chính máy tính này, điện thoại thật sẽ '
                    'không vào được. Muốn dùng điện thoại, chạy backend bằng: '
                    'dotnet run --launch-profile lan',
              ),
            )
          else if (_resultOk && _result != null && _lanUrls.isNotEmpty && !device.maybePhysicalPhone)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Trên điện thoại thật (cùng Wi-Fi) nhập: ${_lanUrls.join('  hoặc  ')}',
                style: TextStyle(color: theme.hintColor),
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
          ...hints,
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({
    required this.title,
    required this.value,
    this.note,
    this.onTap,
    this.highlighted = false,
  });

  final String title;
  final String value;
  final String? note;

  /// Bấm để điền [value] vào ô địa chỉ (chỉ cho các địa chỉ cố định).
  final void Function(String value)? onTap;

  /// Gợi ý phù hợp với thiết bị đang dùng.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tap = onTap;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: highlighted ? theme.colorScheme.primary.withValues(alpha: 0.06) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: tap == null ? null : () => tap(value),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  highlighted ? '$title  (thiết bị này)' : title,
                  style: highlighted ? const TextStyle(fontWeight: FontWeight.w600) : null,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        value,
                        style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (tap != null) ...[
                      const SizedBox(width: 6),
                      Text('Bấm để điền',
                          style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
                    ],
                  ],
                ),
                if (note != null)
                  Text(note!, style: TextStyle(color: theme.hintColor, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
