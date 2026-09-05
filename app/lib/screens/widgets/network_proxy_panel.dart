import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';

class NetworkProxyPanel extends StatefulWidget {
  const NetworkProxyPanel({
    super.key,
    required this.value,
    required this.onChanged,
    this.showFollowGlobal = true,
    this.probeUrl,
  });

  final NetworkProxy value;
  final ValueChanged<NetworkProxy> onChanged;
  final bool showFollowGlobal;
  final String? probeUrl;

  @override
  State<NetworkProxyPanel> createState() => _NetworkProxyPanelState();
}

class _NetworkProxyPanelState extends State<NetworkProxyPanel> {
  late NetworkProxyMode _mode;
  late NetworkProxyType _type;
  late final TextEditingController _host;
  late final TextEditingController _port;
  late final TextEditingController _user;
  late final TextEditingController _pass;
  bool _showPassword = false;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.value.mode;
    if (!widget.showFollowGlobal && _mode == NetworkProxyMode.followGlobal) {
      _mode = NetworkProxyMode.custom;
    }
    _type = widget.value.type;
    _host = TextEditingController(text: widget.value.host);
    _port = TextEditingController(
      text: widget.value.host.trim().isNotEmpty && widget.value.port > 0 ? '${widget.value.port}' : '',
    );
    _user = TextEditingController(text: widget.value.username);
    _pass = TextEditingController(text: widget.value.password);
  }

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  NetworkProxy _build() => NetworkProxy(
    mode: _mode,
    type: _type,
    host: _host.text.trim(),
    port: int.tryParse(_port.text.trim()) ?? 0,
    username: _user.text,
    password: _pass.text,
  );

  void _emit() => widget.onChanged(_build());

  Future<void> _test() async {
    final store = context.read<VaultStore>();
    final proxy = _build();
    if (!proxy.isConfigured) {
      store.notify('请填写主机地址和端口', FeedbackType.warning);
      return;
    }
    setState(() => _testing = true);
    try {
      await testNetworkProxy(proxy, probeUrl: widget.probeUrl);
      store.notify('代理可用');
    } catch (error) {
      store.notify(userFacingError(error, '代理连不上，请检查地址和端口'), FeedbackType.error);
    } finally {
      if (mounted) {
        setState(() => _testing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final line = dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine;
    final modes = <(NetworkProxyMode, String)>[
      if (widget.showFollowGlobal) (NetworkProxyMode.followGlobal, '跟随全局'),
      (NetworkProxyMode.custom, '自定义'),
      (NetworkProxyMode.direct, '直连'),
    ];

    return YuconCard(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.travel_explore, size: 18, color: dark ? const Color(0xFFC4B5FD) : ThemeDefine.kColorPrimary),
              const SizedBox(width: 6),
              Text(
                '网络代理',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: dark ? const Color(0xFFC4B5FD) : ThemeDefine.kColorTitle,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                for (var i = 0; i < modes.length; i++) ...[
                  if (i > 0) Container(width: 1, height: 40, color: line),
                  Expanded(child: _modeTab(modes[i].$1, modes[i].$2, dark)),
                ],
              ],
            ),
          ),
          if (_mode == NetworkProxyMode.followGlobal)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                '使用「我的」里配置的全局代理。还没设置时按直连。',
                style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
              ),
            ),
          if (_mode == NetworkProxyMode.custom) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 124,
                  child: DropdownButtonFormField<NetworkProxyType>(
                    initialValue: _type,
                    isExpanded: true,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                    decoration: _outline(line, label: '协议'),
                    items: const [
                      DropdownMenuItem(value: NetworkProxyType.http, child: Text('HTTP')),
                      DropdownMenuItem(value: NetworkProxyType.https, child: Text('HTTPS')),
                      DropdownMenuItem(value: NetworkProxyType.socks5, child: Text('SOCKS5')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() => _type = value);
                      _emit();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _host,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(fontSize: 14),
                    decoration: _outline(line, label: '主机地址', isRequired: true),
                    onChanged: (_) => _emit(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _port,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 14),
              decoration: _outline(line, label: '端口', isRequired: true),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              style: const TextStyle(fontSize: 14),
              decoration: _outline(line, label: '用户名'),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pass,
              obscureText: !_showPassword,
              style: const TextStyle(fontSize: 14),
              decoration: _outline(
                line,
                label: '密码',
                suffixIcon: secretVisibilityButton(
                  visible: _showPassword,
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onChanged: (_) => _emit(),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _testing ? null : _test,
                style: FilledButton.styleFrom(
                  backgroundColor: dark ? const Color(0xFF3A3548) : ThemeDefine.kColorSoft,
                  foregroundColor: dark ? const Color(0xFFDDD6FE) : ThemeDefine.kColorPrimary,
                  disabledBackgroundColor: dark ? const Color(0xFF3A3548) : ThemeDefine.kColorSoft,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering_error_rounded, size: 18),
                label: Text(_testing ? '测试中' : '测试代理'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _modeTab(NetworkProxyMode mode, String label, bool dark) {
    final selected = _mode == mode;
    return GestureDetector(
      onTap: () {
        setState(() => _mode = mode);
        _emit();
      },
      child: Container(
        height: 40,
        alignment: Alignment.center,
        color: selected ? (dark ? const Color(0xFF3A3548) : ThemeDefine.kColorSoft) : Colors.transparent,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (selected) ...[
              Icon(Icons.check, size: 15, color: dark ? const Color(0xFFDDD6FE) : ThemeDefine.kColorPrimary),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: selected
                    ? (dark ? const Color(0xFFDDD6FE) : ThemeDefine.kColorPrimary)
                    : ThemeDefine.kColorText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _outline(
    Color line, {
    required String label,
    bool isRequired = false,
    Widget? suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: line),
    );
    final labelStyle = TextStyle(fontSize: 13, color: ThemeDefine.kColorText);
    return InputDecoration(
      label: isRequired
          ? Text.rich(
              TextSpan(
                style: labelStyle,
                children: [
                  TextSpan(text: label),
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: ThemeDefine.kColorPrimary, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          : Text(label, style: labelStyle),
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      isDense: true,
      filled: false,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: ThemeDefine.kColorPrimary),
      ),
    );
  }
}
