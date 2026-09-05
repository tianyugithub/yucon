import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/model_pricing.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/site_login_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/network_proxy_panel.dart';
import 'package:vault/screens/widgets/ui.dart';

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({super.key, this.accountId});

  final String? accountId;

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  late AccountDraft _form;
  late final TextEditingController _baseUrl;
  late final TextEditingController _alias;
  late final TextEditingController _siteName;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _accessToken;
  late final TextEditingController _userId;
  late final TextEditingController _topupRatio;
  late final TextEditingController _apiUrls;
  bool _saving = false;
  bool _capturing = false;
  bool _showPassword = false;
  bool _showAccessToken = false;
  bool _showApiUrls = false;

  @override
  void initState() {
    super.initState();
    final store = context.read<VaultStore>();
    final account = widget.accountId == null ? null : store.accountById(widget.accountId!);
    _form = store.toAccountDraft(account);
    if (!getPlatformPreset(_form.platformType).supportsAccessToken) {
      _form.authMode = AuthMode.password;
    }
    _baseUrl = TextEditingController(text: _form.baseUrl)..addListener(() => setState(() {}));
    _alias = TextEditingController(text: _form.alias)..addListener(() => setState(() {}));
    _siteName = TextEditingController(text: _form.siteName);
    _username = TextEditingController(text: _form.username)..addListener(() => setState(() {}));
    _password = TextEditingController();
    _accessToken = TextEditingController();
    _userId = TextEditingController(text: _form.userId);
    _topupRatio = TextEditingController(text: topupRatioInputText(_form.topupRatio));
    _apiUrls = TextEditingController(text: _form.apiUrls.join('\n'));
    _showApiUrls = _form.apiUrls.isNotEmpty;
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _alias.dispose();
    _siteName.dispose();
    _username.dispose();
    _password.dispose();
    _accessToken.dispose();
    _userId.dispose();
    _topupRatio.dispose();
    _apiUrls.dispose();
    super.dispose();
  }

  bool get _isEditing => _form.id != null;

  bool get _expired {
    if (_form.id == null) {
      return false;
    }
    return context.read<VaultStore>().accountById(_form.id!)?.status == AccountStatus.expired;
  }

  bool get _isSub2 => _form.platformType == PlatformType.sub2api;

  bool get _useWebLogin => _form.authMode == AuthMode.password || _isSub2;

  String get _title => _expired ? '重新登录' : (_isEditing ? '编辑账号' : '添加账号');

  bool get _usesInsecureHttp {
    final raw = _baseUrl.text.trim();
    if (raw.isEmpty) {
      return false;
    }
    final parsed = Uri.tryParse(RegExp(r'^https?://', caseSensitive: false).hasMatch(raw) ? raw : 'https://$raw');
    if (parsed == null || parsed.scheme.toLowerCase() != 'http') {
      return false;
    }
    final host = parsed.host.toLowerCase();
    return host != 'localhost' && host != '127.0.0.1' && host != '10.0.2.2';
  }

  String get _tip {
    if (_expired) {
      return _useWebLogin
        ? '当前站点登录已过期。点下方按钮会打开站点页面，若仍显示已登录会自动返回。'
        : '当前站点登录已过期。请重新填写访问令牌后再保存。';
    }
    return _useWebLogin
        ? '连接时会打开站点页面。若已经登录会自动返回钥仓；未登录则在页面里完成验证后再返回。'
        : '请填写个人设置里的访问令牌。额度和密钥会从站点实时读取。';
  }

  String get _passwordHint {
    if (_expired) {
      return '会填进站点登录页，也可留空到页面里自己输入。登录成功后密码会加密保存在本机。';
    }
    if (_isEditing) {
      return '留空则继续使用已保存的登录状态。要重新登录时再填，成功后会更新本机保存的密码。';
    }
    return '会填进站点登录页，也可留空到页面里自己输入。登录成功后密码会加密保存在本机。';
  }

  Future<void> _save() async {
    final store = context.read<VaultStore>();
    _form.baseUrl = _baseUrl.text;
    _form.alias = _alias.text;
    _form.siteName = _siteName.text;
    _form.username = _username.text;
    _form.password = _password.text;
    _form.accessToken = _accessToken.text;
    _form.userId = _userId.text;
    _form.apiUrls = parseExtraApiUrls(_apiUrls.text, baseUrl: _baseUrl.text);
    final ratioText = _topupRatio.text.trim().replaceAll(',', '');
    if (ratioText.isEmpty) {
      _form.topupRatio = 1;
    } else {
      final parsed = double.tryParse(ratioText);
      if (parsed == null || parsed <= 0) {
        store.notify('充值比例需大于 0', FeedbackType.warning);
        return;
      }
      _form.topupRatio = parsed;
    }
    if (_form.baseUrl.trim().isEmpty) {
      store.notify('请填写站点地址', FeedbackType.warning);
      return;
    }
    if (_form.proxy.mode == NetworkProxyMode.custom && !_form.proxy.isConfigured) {
      store.notify('请填写主机地址和端口', FeedbackType.warning);
      return;
    }
    if (!getPlatformPreset(_form.platformType).supportsAccessToken) {
      _form.authMode = AuthMode.password;
    }
    setState(() => _saving = true);
    try {
      if (_useWebLogin &&
          _form.accessToken.trim().isEmpty &&
          (!_isEditing || _form.password.isNotEmpty || _expired)) {
        setState(() => _capturing = true);
        final session = await captureSiteSession(
          context,
          baseUrl: _form.baseUrl,
          platformType: _form.platformType,
          email: _form.username,
          password: _form.password,
          proxy: store.resolvedProxy(_form.proxy),
        );
        _form.accessToken = session.accessToken;
        _form.refreshToken = session.refreshToken;
        _form.cookies = session.cookies;
        if (_form.userId.trim().isEmpty && session.userId.isNotEmpty) {
          _form.userId = session.userId;
          _userId.text = session.userId;
        }
        if (_form.username.trim().isEmpty && session.username.isNotEmpty) {
          _form.username = session.username;
          _username.text = session.username;
        }
      }
      final account = await store.saveAccount(_form);
      store.notify(_expired ? '已重新登录并同步' : (_isEditing ? '账号已重新同步' : '账号已连接并同步'));
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AccountDetailScreen(accountId: account.id)),
      );
    } catch (error) {
      store.notify(userFacingError(error, '连接失败'), FeedbackType.error);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _capturing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preset = getPlatformPreset(_form.platformType);
    final previewName = _alias.text.trim().isNotEmpty
        ? _alias.text.trim()
        : (_username.text.trim().isNotEmpty ? _username.text.trim() : '未命名账号');
    final previewHost = displayDomain(_baseUrl.text).isEmpty ? '未填写站点地址' : displayDomain(_baseUrl.text);
    final saveLabel = _capturing
        ? '正在打开站点登录…'
        : (_expired ? '重新登录' : (_isEditing ? '保存并同步' : '连接账号'));

    return SecureScope(
      child: Scaffold(
      appBar: YuconAppBar(title: _title, subtitle: '连接你的站点账号'),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(15, 4, 15, 24),
        children: [
          TipBanner(text: _tip),
          if (_usesInsecureHttp)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: TipBanner(
                text: '当前是 http 地址。正式版系统会拦截非本机的明文站点，请改用 https，或只在调试包里连接局域网。',
              ),
            ),
          YuconCard(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                SquareIcon(
                  size: 33,
                  radius: 10,
                  color: Color(preset.color),
                  child: Text(
                    preset.shortLabel,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(previewName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        '$previewHost · ${preset.label}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle(text: '账号类型'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in platformPresets.values)
                GestureDetector(
                  onTap: () => setState(() {
                    _form.platformType = item.type;
                    if (!item.supportsAccessToken) {
                      _form.authMode = AuthMode.password;
                      _form.accessToken = '';
                    }
                  }),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 7, 12, 7),
                    decoration: BoxDecoration(
                      color: _form.platformType == item.type ? Color(item.lightColor) : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _form.platformType == item.type ? Color(item.color) : ThemeDefine.kColorLine,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SquareIcon(
                          size: 22,
                          radius: 7,
                          color: Color(item.color),
                          child: Text(
                            item.shortLabel,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _form.platformType == item.type ? Color(item.color) : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(1, 8, 1, 0),
            child: Text(preset.description, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12)),
          ),
          const SectionTitle(text: '站点与备注'),
          YuconCard(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Column(
              children: [
                LabeledField(
                  label: '站点地址',
                  requiredMark: true,
                  child: TextField(
                    controller: _baseUrl,
                    keyboardType: TextInputType.url,
                    decoration: inCardInput(hint: _isSub2 ? 'https://www.miapi.cc' : '例如：https://api.xxx.com'),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: () => setState(() => _showApiUrls = !_showApiUrls),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        _showApiUrls ? '收起' : '其他调用地址',
                        style: const TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showApiUrls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _apiUrls,
                          minLines: 2,
                          maxLines: 5,
                          keyboardType: TextInputType.url,
                          decoration: inCardInput(hint: '每行一个，可留空'),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '复制密钥时默认用上面的站点地址。若站点还有别的调用地址，再填在这里。',
                          style: TextStyle(color: ThemeDefine.kColorText, fontSize: 11, height: 1.45),
                        ),
                      ],
                    ),
                  ),
                LabeledField(
                  label: '本地备注',
                  child: TextField(
                    controller: _alias,
                    decoration: inCardInput(hint: '例如：主账号'),
                  ),
                ),
                LabeledField(
                  label: '站点名称',
                  child: TextField(
                    controller: _siteName,
                    decoration: inCardInput(hint: '可留空，默认使用域名'),
                  ),
                ),
                LabeledField(
                  label: '充值比例',
                  last: true,
                  hint: '站点按美元扣费。这里填多少人民币等于 1 美元额度，默认 1。例如 1 元人民币 = 1 美元填 1，2.5 元人民币 = 1 美元填 2.5。',
                  child: TextField(
                    controller: _topupRatio,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: inCardInput(hint: '默认 1'),
                  ),
                ),
              ],
            ),
          ),
          NetworkProxyPanel(
            value: _form.proxy,
            probeUrl: _baseUrl.text.trim().isEmpty ? null : _baseUrl.text.trim(),
            onChanged: (proxy) => setState(() => _form.proxy = proxy),
          ),
          const SectionTitle(text: '登录方式'),
          if (preset.supportsAccessToken)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: _authModeCard(
                      title: '用户名密码',
                      subtitle: '打开站点页面登录',
                      selected: _form.authMode == AuthMode.password,
                      onTap: () => setState(() => _form.authMode = AuthMode.password),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _authModeCard(
                      title: '访问令牌',
                      subtitle: '从个人设置粘贴',
                      selected: _form.authMode == AuthMode.accessToken,
                      onTap: () => setState(() => _form.authMode = AuthMode.accessToken),
                    ),
                  ),
                ],
              ),
            ),
          YuconCard(
            padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
            child: Column(
              children: [
                if (_form.authMode == AuthMode.password || _isSub2) ...[
                  LabeledField(
                    label: preset.identityLabel,
                    child: TextField(
                      controller: _username,
                      keyboardType: _isSub2 ? TextInputType.emailAddress : TextInputType.text,
                      decoration: inCardInput(hint: preset.identityPlaceholder),
                    ),
                  ),
                  LabeledField(
                    label: '密码',
                    last: true,
                    hint: _passwordHint,
                    child: TextField(
                      controller: _password,
                      obscureText: !_showPassword,
                      decoration: inCardInput(
                        hint: '登录成功后加密保存在本机',
                        suffix: secretVisibilityButton(
                          visible: _showPassword,
                          onPressed: () => setState(() => _showPassword = !_showPassword),
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '点「连接账号」会打开站点官方登录页。人机验证在站点上完成，登录成功后自动返回钥仓。',
                      style: TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.45),
                    ),
                  ),
                ] else ...[
                  LabeledField(
                    label: '访问令牌',
                    requiredMark: !_isEditing,
                    hint: '请填写个人设置里的访问令牌，不要填 sk- 开头的密钥。',
                    child: TextField(
                      controller: _accessToken,
                      obscureText: !_showAccessToken,
                      decoration: inCardInput(
                        hint: '个人设置里的访问令牌',
                        suffix: secretVisibilityButton(
                          visible: _showAccessToken,
                          onPressed: () => setState(() => _showAccessToken = !_showAccessToken),
                        ),
                      ),
                    ),
                  ),
                  LabeledField(
                    label: '用户 ID',
                    last: true,
                    hint: '可留空。连不上时再到个人设置抄数字 ID。',
                    child: TextField(
                      controller: _userId,
                      keyboardType: TextInputType.number,
                      decoration: inCardInput(hint: '可留空，一般会自动识别'),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          PrimaryButton(label: saveLabel, busy: _saving, onPressed: _save),
        ],
      ),
    ),
    );
  }

  Widget _authModeCard({
    required String title,
    required String subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? ThemeDefine.kColorSoft : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? ThemeDefine.kColorPrimary : ThemeDefine.kColorLine),
          boxShadow: selected ? null : ThemeDefine.kCardShadow,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text(subtitle, style: const TextStyle(color: ThemeDefine.kColorText, fontSize: 12, height: 1.35)),
          ],
        ),
      ),
    );
  }
}
