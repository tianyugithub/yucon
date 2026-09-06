import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/api/site_detect.dart';
import 'package:vault/app/api/sub2api.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/identity/site_register_flow.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/model_pricing.dart';
import 'package:vault/screens/account_detail_screen.dart';
import 'package:vault/screens/identity_screen.dart';
import 'package:vault/screens/site_login_screen.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/identity_brand_icon.dart';
import 'package:vault/screens/widgets/identity_login_sheet.dart';
import 'package:vault/screens/widgets/network_proxy_panel.dart';
import 'package:vault/screens/widgets/platform_brand_icon.dart';
import 'package:vault/screens/widgets/site_auth_progress.dart';
import 'package:vault/screens/widgets/ui.dart';

enum AccountFormIntent { add, register }

enum _SiteSignMethod { password, accessToken, identity, google, github }

enum _SiteAuthFlow { register, login }

class AccountFormScreen extends StatefulWidget {
  const AccountFormScreen({
    super.key,
    this.accountId,
    this.intent = AccountFormIntent.add,
  });

  final String? accountId;
  final AccountFormIntent intent;

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
  SiteRegisterStage? _registerStage;
  String _registerDetail = '';
  String? _registerError;
  _SiteAuthFlow? _authFlow;
  bool _showPassword = false;
  bool _showAccessToken = false;
  _SiteSignMethod _signMethod = _SiteSignMethod.password;
  String? _identityAccountId;
  String? _checkingIdentityId;
  SiteStatus? _siteStatus;
  Timer? _probeTimer;
  String _probedUrl = '';
  bool _userPickedPlatform = false;
  bool _showAdvanced = false;
  bool _probing = false;
  late final AuthMode _savedAuthMode;

  @override
  void initState() {
    super.initState();
    final store = context.read<VaultStore>();
    final account = widget.accountId == null
        ? null
        : store.accountById(widget.accountId!);
    _form = store.toAccountDraft(account);
    _userPickedPlatform = _form.id != null;
    if (!getPlatformPreset(_form.platformType).supportsAccessToken) {
      _form.authMode = AuthMode.password;
    }
    _savedAuthMode = _form.authMode;
    _baseUrl = TextEditingController(text: _form.baseUrl)
      ..addListener(() {
        setState(() {});
        _userPickedPlatform = false;
        _scheduleProbe();
      });
    _alias = TextEditingController(text: _form.alias)
      ..addListener(() => setState(() {}));
    _siteName = TextEditingController(text: _form.siteName);
    _username = TextEditingController(text: _form.username)
      ..addListener(() => setState(() {}));
    final registerPassword =
        widget.intent == AccountFormIntent.register && _form.password.isEmpty
        ? generateSiteRegisterPassword()
        : _form.password;
    _password = TextEditingController(text: registerPassword);
    if (widget.intent == AccountFormIntent.register) {
      _showPassword = true;
    }
    _accessToken = TextEditingController(text: _form.accessToken);
    _userId = TextEditingController(text: _form.userId);
    _topupRatio = TextEditingController(
      text: topupRatioInputText(_form.topupRatio),
    );
    _apiUrls = TextEditingController(text: _form.apiUrls.join('\n'));
    _showAdvanced = widget.accountId != null;
    if (_form.authMode == AuthMode.accessToken) {
      _signMethod = _SiteSignMethod.accessToken;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _probeSite());
  }

  @override
  void dispose() {
    _probeTimer?.cancel();
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
    return context.read<VaultStore>().accountById(_form.id!)?.status ==
        AccountStatus.expired;
  }

  bool get _isSub2 => _form.platformType == PlatformType.sub2api;

  bool get _isRegister =>
      !_isEditing && widget.intent == AccountFormIntent.register;

  bool get _useWebLogin => _useIdentityMethod;

  bool get _useNativePasswordLogin =>
      !_isRegister && _signMethod == _SiteSignMethod.password;

  bool get _useIdentity =>
      _signMethod == _SiteSignMethod.google ||
      _signMethod == _SiteSignMethod.github;

  bool get _useIdentityMethod =>
      _signMethod == _SiteSignMethod.identity || _useIdentity;

  bool get _showIdentityAuth =>
      !_savedAsAccessToken && !_isRegister && _useIdentityMethod;

  bool get _savedAsAccessToken =>
      _isEditing && !_isSub2 && _savedAuthMode == AuthMode.accessToken;

  bool get _issuesLoginToken => !_isSub2 && _useIdentity;

  String get _identityProvider => _signMethod == _SiteSignMethod.github
      ? githubIdentityProvider
      : googleIdentityProvider;

  String get _title {
    if (_expired) {
      return '重新登录';
    }
    if (_isEditing) {
      return '编辑账号';
    }
    return _isRegister ? '注册账号' : '添加账号';
  }

  String get _appBarSubtitle {
    if (_isRegister) {
      return '调用站点接口注册，邮箱收验证码';
    }
    if (_expired) {
      return '登录已过期，重新接入即可';
    }
    if (_isEditing) {
      return '保存后会同步余额和密钥';
    }
    if (_useIdentityMethod) {
      return '用已记住的 Google / GitHub';
    }
    if (_signMethod == _SiteSignMethod.accessToken) {
      return '粘贴个人设置里的访问令牌';
    }
    return '调用站点接口自动登录';
  }

  bool get _usesInsecureHttp {
    final raw = _baseUrl.text.trim();
    if (raw.isEmpty) {
      return false;
    }
    final parsed = Uri.tryParse(
      RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)
          ? raw
          : 'https://$raw',
    );
    if (parsed == null || parsed.scheme.toLowerCase() != 'http') {
      return false;
    }
    final host = parsed.host.toLowerCase();
    return host != 'localhost' && host != '127.0.0.1' && host != '10.0.2.2';
  }

  String get _tip {
    if (_expired) {
      if (_savedAsAccessToken) {
        return '当前站点登录已过期。请重新填写访问令牌后再保存。';
      }
      if (_useIdentityMethod) {
        return '当前站点登录已过期。点下方按钮会打开站点页面，若仍显示已登录会自动返回。可用已记住的 Google / GitHub 身份。';
      }
      return '当前站点登录已过期。点下方会用用户名和密码自动登录，人机验证由「验证码服务」代解。';
    }
    return _useIdentityMethod
        ? (_isSub2
              ? '选择已记住的 Google 或 GitHub 身份。点「用此身份打开站点」会先确认这份登录是否有效；不通过会提示，通过后才打开站点登录页并点对应按钮。Cloudflare 如有需要请手动点过。'
              : '选择已记住的 Google 或 GitHub 身份。点「用此身份打开站点」会先确认这份登录是否有效；不通过会提示，通过后才打开站点。成功后会申请访问令牌，之后用令牌登录。')
        : (_signMethod == _SiteSignMethod.accessToken
              ? '请填写个人设置里的访问令牌。额度和密钥会从站点实时读取。'
              : '填写用户名和密码后会调用站点接口自动登录。需要人机验证时由「验证码服务」代解。');
  }

  String get _passwordHint {
    if (_expired) {
      return '会用来自动登录。也可留空，使用本机已保存的密码。';
    }
    if (_isEditing) {
      return _password.text.isNotEmpty
          ? '已保存在本机，点右侧眼睛可查看。改了会在下次保存时更新。'
          : '留空则继续使用已保存的登录状态。要重新登录时再填，成功后会更新本机保存的密码。';
    }
    if (_isRegister) {
      return '可自己填写，或点右侧「随机」生成。注册成功后会写入用户名密码并加密保存在本机。';
    }
    return '会用来自动登录，成功后加密保存在本机。需要人机验证时由「验证码服务」代解。';
  }

  void _fillRandomRegisterPassword() {
    final next = generateSiteRegisterPassword();
    _password.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _showPassword = true);
  }

  void _scheduleProbe() {
    _probeTimer?.cancel();
    _probeTimer = Timer(
      const Duration(milliseconds: 700),
      () => unawaited(_probeSite()),
    );
  }

  String? _normalizedBaseUrl() {
    final raw = _baseUrl.text.trim();
    if (raw.isEmpty) {
      return null;
    }
    return normalizeBaseUrl(
      RegExp(r'^https?://', caseSensitive: false).hasMatch(raw)
          ? raw
          : 'https://$raw',
    );
  }

  Future<void> _probeSite() async {
    final url = _normalizedBaseUrl();
    if (url == null) {
      if (mounted) {
        setState(() {
          _siteStatus = null;
          _probedUrl = '';
          _probing = false;
        });
      }
      return;
    }
    final allowSwitch = !_isEditing && !_userPickedPlatform;
    final cacheKey = allowSwitch
        ? 'detect|$url'
        : '${_form.platformType.name}|$url';
    if (cacheKey == _probedUrl && _siteStatus != null) {
      return;
    }
    if (mounted) {
      setState(() => _probing = true);
    }
    final store = context.read<VaultStore>();
    try {
      final detected = allowSwitch
          ? await runWithProxy(
              store.resolvedProxy(_form.proxy),
              () => detectSitePlatform(url),
            )
          : null;
      if (!mounted || _normalizedBaseUrl() != url) {
        return;
      }
      if (detected != null && !_userPickedPlatform && !_isEditing) {
        _probedUrl = cacheKey;
        _applyDetectedPlatform(detected);
        return;
      }
      final status = await runWithProxy(
        store.resolvedProxy(_form.proxy),
        () => _isSub2 ? fetchSub2SiteStatus(url) : fetchSiteStatus(url),
      );
      if (!mounted || _normalizedBaseUrl() != url) {
        return;
      }
      _probedUrl = cacheKey;
      _applySiteStatus(status);
    } catch (_) {
      if (mounted) {
        setState(() {});
      }
    } finally {
      if (mounted) {
        setState(() => _probing = false);
      }
    }
  }

  void _applyDetectedPlatform(DetectedSite detected) {
    if (_form.platformType != detected.type) {
      _form.platformType = detected.type;
      final preset = getPlatformPreset(detected.type);
      if (!preset.supportsAccessToken) {
        _form.authMode = AuthMode.password;
        _form.accessToken = '';
        if (_signMethod == _SiteSignMethod.accessToken) {
          _signMethod = _SiteSignMethod.password;
        }
      }
    }
    _applySiteStatus(detected.status);
  }

  void _applySiteStatus(SiteStatus status) {
    if (_siteName.text.trim().isEmpty && status.systemName.trim().isNotEmpty) {
      _siteName.text = status.systemName.trim();
      _form.siteName = _siteName.text;
    }
    setState(() {
      _siteStatus = status;
    });
  }

  String? _resolvedIdentityId() {
    if (!_useIdentity) {
      return null;
    }
    return _identityAccountId ??
        context.read<VaultStore>().identitySessionKey(_identityProvider);
  }

  Future<bool> _ensureIdentityReady() async {
    final store = context.read<VaultStore>();
    final provider = _identityProvider;
    var id = _resolvedIdentityId();
    if (id == null || id.isEmpty) {
      final created = await showIdentityLoginEditor(
        context: context,
        provider: provider,
      );
      if (!mounted) {
        return false;
      }
      if (created == null) {
        store.notify(
          '请先选择一个${identityLoginTitle(provider)}',
          FeedbackType.warning,
        );
        return false;
      }
      setState(() => _identityAccountId = created.id);
      id = created.id;
    }
    return _refreshIdentitySession(provider, id);
  }

  Future<bool> _refreshIdentitySession(
    String provider,
    String accountId,
  ) async {
    if (_checkingIdentityId == accountId) {
      return false;
    }
    setState(() => _checkingIdentityId = accountId);
    try {
      final store = context.read<VaultStore>();
      if (accountId.trim().isNotEmpty) {
        await store.selectIdentityLogin(provider, accountId);
      }
      if (!mounted) {
        return false;
      }
      final fresh = await store.verifyIdentitySession(
        provider,
        accountId: accountId,
        proxy: store.resolvedProxy(_form.proxy),
      );
      if (!mounted) {
        return false;
      }
      if (fresh == IdentitySessionFreshness.alive) {
        return true;
      }
      store.notify(
        identitySessionFailureHint(provider, fresh),
        FeedbackType.warning,
      );
      return false;
    } finally {
      if (mounted) {
        setState(() => _checkingIdentityId = null);
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _checkingIdentityId != null) {
      return;
    }
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
    if (_useIdentityMethod && !_useIdentity) {
      store.notify('请先选择一个 Google 或 GitHub 身份', FeedbackType.warning);
      return;
    }
    if (_isRegister) {
      final email = _username.text.trim();
      if (!email.contains('@')) {
        store.notify('请填写用于注册的邮箱', FeedbackType.warning);
        return;
      }
      final password = _password.text.trim();
      if (password.isEmpty) {
        store.notify('请填写密码，或点随机生成', FeedbackType.warning);
        return;
      }
      _form.username = email;
      _form.password = password;
      _form.alias = mailboxLocalPart(email);
      _alias.text = _form.alias;
      _signMethod = _SiteSignMethod.password;
    } else if (_form.password.trim().isEmpty && (_form.id ?? '').isNotEmpty) {
      _form.password = store.passwordForAccount(_form.id!);
    }
    final storedPassword = (_form.id ?? '').isEmpty
        ? ''
        : store.passwordForAccount(_form.id!);
    final passwordChanged =
        _form.password.isNotEmpty && _form.password != storedPassword;
    final needNativeLogin =
        _useNativePasswordLogin &&
        _form.accessToken.trim().isEmpty &&
        (!_isEditing || _expired || passwordChanged);
    if (needNativeLogin) {
      if (_form.username.trim().isEmpty) {
        store.notify(_isSub2 ? '请填写登录邮箱' : '请填写用户名', FeedbackType.warning);
        return;
      }
      if (_isSub2 && !_form.username.contains('@')) {
        store.notify('请填写用于登录的邮箱', FeedbackType.warning);
        return;
      }
      if (_form.password.trim().isEmpty) {
        store.notify('请填写密码', FeedbackType.warning);
        return;
      }
    }
    if (_form.proxy.mode == NetworkProxyMode.custom &&
        !_form.proxy.isConfigured) {
      store.notify('请填写主机地址和端口', FeedbackType.warning);
      return;
    }
    if (_isRegister ||
        !getPlatformPreset(_form.platformType).supportsAccessToken) {
      _form.authMode = AuthMode.password;
      if (_signMethod == _SiteSignMethod.accessToken) {
        _signMethod = _SiteSignMethod.password;
      }
    } else {
      _form.authMode = _signMethod == _SiteSignMethod.accessToken
          ? AuthMode.accessToken
          : AuthMode.password;
    }
    _form.issueLoginAccessToken = _isRegister ? false : _issuesLoginToken;
    if (_savedAsAccessToken && _expired && _form.accessToken.trim().isEmpty) {
      store.notify('请填写访问令牌', FeedbackType.warning);
      return;
    }
    if (_useIdentity && !await _ensureIdentityReady()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      if (_isRegister) {
        setState(() {
          _capturing = true;
          _registerError = null;
          _authFlow = _SiteAuthFlow.register;
          _registerStage = SiteRegisterStage.checking;
          _registerDetail = '读取站点公开设置';
        });
        final proxy = store.resolvedProxy(_form.proxy);
        final outcome = await runWithProxy(
          proxy,
          () => _form.platformType == PlatformType.sub2api
              ? registerSub2SiteNatively(
                  baseUrl: _form.baseUrl,
                  email: _form.username,
                  password: _form.password,
                  solver: store.settings.captchaSolver,
                  requestCode: _requestManualCode,
                  onProgress: _onRegisterProgress,
                )
              : registerNewApiSiteNatively(
                  baseUrl: _form.baseUrl,
                  email: _form.username,
                  password: _form.password,
                  solver: store.settings.captchaSolver,
                  requestCode: _requestManualCode,
                  onProgress: _onRegisterProgress,
                ),
        );
        _form.accessToken = outcome.accessToken;
        _form.refreshToken = outcome.refreshToken;
        _form.username = _username.text.trim();
        _form.authMode = AuthMode.password;
        _form.issueLoginAccessToken = false;
        if (outcome.cookies.isNotEmpty) {
          _form.cookies = outcome.cookies;
        }
        if (_form.userId.trim().isEmpty && outcome.userId.isNotEmpty) {
          _form.userId = outcome.userId;
          _userId.text = outcome.userId;
        }
        setState(() {
          _registerStage = SiteRegisterStage.done;
          _registerDetail = '正在同步账号信息…';
        });
      } else if (needNativeLogin) {
        setState(() {
          _capturing = true;
          _registerError = null;
          _authFlow = _SiteAuthFlow.login;
          _registerStage = SiteRegisterStage.checking;
          _registerDetail = '读取站点公开设置';
        });
        final proxy = store.resolvedProxy(_form.proxy);
        final outcome = await runWithProxy(
          proxy,
          () => _form.platformType == PlatformType.sub2api
              ? loginSub2SiteNatively(
                  baseUrl: _form.baseUrl,
                  email: _form.username,
                  password: _form.password,
                  solver: store.settings.captchaSolver,
                  onProgress: _onRegisterProgress,
                )
              : loginNewApiSiteNatively(
                  baseUrl: _form.baseUrl,
                  username: _form.username,
                  password: _form.password,
                  solver: store.settings.captchaSolver,
                  onProgress: _onRegisterProgress,
                ),
        );
        _form.accessToken = outcome.accessToken;
        _form.refreshToken = outcome.refreshToken;
        _form.authMode = AuthMode.password;
        if (outcome.cookies.isNotEmpty) {
          _form.cookies = outcome.cookies;
        }
        if (_form.userId.trim().isEmpty && outcome.userId.isNotEmpty) {
          _form.userId = outcome.userId;
          _userId.text = outcome.userId;
        }
        setState(() {
          _registerStage = SiteRegisterStage.done;
          _registerDetail = '正在同步账号信息…';
        });
      } else if (_useWebLogin &&
          _form.accessToken.trim().isEmpty &&
          (!_isEditing ||
              _form.password.isNotEmpty ||
              _expired ||
              _useIdentity)) {
        setState(() => _capturing = true);
        final session = await captureSiteSession(
          context,
          baseUrl: _form.baseUrl,
          platformType: _form.platformType,
          email: _form.username,
          password: _form.password,
          proxy: store.resolvedProxy(_form.proxy),
          googleAccountId: _signMethod == _SiteSignMethod.google
              ? _resolvedIdentityId()
              : null,
          githubAccountId: _signMethod == _SiteSignMethod.github
              ? _resolvedIdentityId()
              : null,
          resetSiteSession:
              !_isEditing || _useIdentity || _form.password.isNotEmpty,
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
      final issuedLoginToken =
          _issuesLoginToken &&
          newApiAccessTokenIsFresh(
            store.sessionByAccount(account.id)?.accessToken ?? '',
          );
      store.notify(
        _expired
            ? '已重新登录并同步'
            : (_isEditing
                  ? '账号已重新同步'
                  : (_isRegister
                        ? '账号已同步，邮箱和密码已写入用户名密码登录'
                        : (issuedLoginToken
                              ? '账号已同步，已用访问令牌登录'
                              : (_issuesLoginToken
                                    ? '账号已同步。访问令牌未申请到，可稍后在站点个人设置里生成'
                                    : '账号已自动登录并同步')))),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AccountDetailScreen(accountId: account.id),
        ),
      );
    } catch (error) {
      final message = userFacingError(error, '连接失败');
      if (_registerStage != null && mounted) {
        setState(() => _registerError = message);
      }
      store.notify(message, FeedbackType.error);
    } finally {
      if (mounted) {
        if (_registerError != null) {
          setState(() {
            _saving = false;
            _capturing = false;
          });
        } else {
          setState(() {
            _saving = false;
            _capturing = false;
            _registerStage = null;
            _registerDetail = '';
            _authFlow = null;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<VaultStore>();
    final preset = getPlatformPreset(_form.platformType);
    final checkingIdentity = _checkingIdentityId != null;
    final registerUiActive =
        (_capturing || _registerError != null) && _registerStage != null;
    final saveLabel = checkingIdentity
        ? '正在确认身份…'
        : registerUiActive
        ? (_registerError != null
              ? (_authFlow == _SiteAuthFlow.login ? '重试登录' : '重试注册')
              : (_registerStage == SiteRegisterStage.done
                    ? '正在同步账号…'
                    : (_authFlow == _SiteAuthFlow.login ? '登录中…' : '注册中…')))
        : _capturing
        ? (_useIdentityMethod ? '正在用身份打开站点…' : '正在自动登录…')
        : (_expired
              ? (_useNativePasswordLogin ? '自动登录' : '重新登录')
              : (_isEditing
                    ? '保存并同步'
                    : (_useIdentityMethod
                          ? '用此身份打开站点'
                          : (_isRegister ? '注册账号' : '自动登录'))));
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bottomPad = MediaQuery.paddingOf(context).bottom;
    final ink = dark ? ThemeDefine.kColorDarkTitle : ThemeDefine.kColorTitle;

    return SecureScope(
      child: Scaffold(
        appBar: YuconAppBar(title: _title, subtitle: _appBarSubtitle),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(15, 8, 15, 24),
                    children: [
                      if (_isEditing) TipBanner(text: _tip),
                      if (_usesInsecureHttp)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: TipBanner(
                            text: '当前是 http 地址。正式版系统会拦截非本机的明文站点，请改用 https，或只在调试包里连接局域网。',
                          ),
                        ),
                      _siteCard(preset, dark, ink),
                      if (_showAccessMethod) ...[
                        const SizedBox(height: 12),
                        _accessCard(preset, store, dark, ink),
                      ],
                      if (_savedAsAccessToken) ...[
                        const SizedBox(height: 12),
                        YuconCard(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: _credentialFields(preset, store),
                        ),
                      ],
                      if (_isRegister) ...[
                        const SizedBox(height: 12),
                        _registerCard(preset, store),
                      ],
                      if (_showIdentityAuth) ...[
                        const SizedBox(height: 12),
                        ..._identityGroupCards(store, dark),
                      ],
                      const SizedBox(height: 12),
                      _advancedCard(dark, ink),
                      if (_showAdvanced)
                        NetworkProxyPanel(
                          value: _form.proxy,
                          probeUrl: _baseUrl.text.trim().isEmpty
                              ? null
                              : _baseUrl.text.trim(),
                          onChanged: (proxy) {
                            setState(() => _form.proxy = proxy);
                            _scheduleProbe();
                          },
                        ),
                    ],
                  ),
                ),
                _bottomBar(
                  dark: dark,
                  bottomPad: bottomPad,
                  label: saveLabel,
                  busy: _saving || checkingIdentity,
                ),
              ],
            ),
            if (registerUiActive)
              SiteAuthProgressScrim(
                title: _authFlow == _SiteAuthFlow.login ? '自动登录进度' : '自动注册进度',
                steps: _authFlow == _SiteAuthFlow.login
                    ? siteLoginProgressSteps
                    : siteRegisterProgressSteps,
                current: _registerStage,
                detail: _registerDetail,
                error: _registerError,
                onRetry: _save,
                onDismiss: _dismissAuthProgress,
              ),
          ],
        ),
      ),
    );
  }

  bool get _showAccessMethod => !_savedAsAccessToken && !_isRegister;

  bool get _embedCredentials =>
      !_isRegister &&
      !_useIdentityMethod &&
      (_signMethod == _SiteSignMethod.password ||
          (_signMethod == _SiteSignMethod.accessToken && !_isSub2));

  String get _signMethodHint {
    switch (_signMethod) {
      case _SiteSignMethod.accessToken:
        return '填写个人设置里的访问令牌，不要填 sk- 开头的密钥。';
      case _SiteSignMethod.identity:
      case _SiteSignMethod.google:
      case _SiteSignMethod.github:
        return '先选一份已记住的身份。点底部按钮时会先确认这份登录是否有效。';
      case _SiteSignMethod.password:
        return '调用站点接口登录。需要人机验证时由「验证码服务」代解。';
    }
  }

  Widget _siteCard(PlatformPreset preset, bool dark, Color ink) {
    final host = displayDomain(_baseUrl.text);
    final detectedName = _siteName.text.trim();
    final title = host.isEmpty
        ? (_isRegister ? '新站点' : '接入站点')
        : (detectedName.isNotEmpty ? detectedName : host);
    final subtitle = host.isEmpty
        ? '填写地址后会自动识别平台'
        : (detectedName.isNotEmpty && detectedName != host
              ? '$host · ${preset.label}'
              : preset.label);
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PlatformBrandIcon(type: preset.type, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.35,
                        height: 1.2,
                        color: ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ThemeDefine.kColorText,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              if (_probing)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _segmentBar(
            dark: dark,
            embedded: true,
            children: [
              for (final item in platformPresets.values)
                _segmentTab(
                  selected: _form.platformType == item.type,
                  dark: dark,
                  onTap: () => _onPickPlatform(item),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PlatformBrandIcon(type: item.type, size: 16, radius: 4),
                      const SizedBox(width: 6),
                      Text(
                        item.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          height: 1,
                          color: _form.platformType == item.type
                              ? ink
                              : ThemeDefine.kColorText,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          LabeledField(
            label: '站点地址',
            requiredMark: true,
            last: true,
            child: TextField(
              controller: _baseUrl,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: _boxInput(
                hint: _isSub2 ? 'https://www.miapi.cc' : 'https://api.xxx.com',
              ),
            ),
          ),
          if (_probing && host.isNotEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '正在识别站点能力…',
                style: TextStyle(
                  color: ThemeDefine.kColorText,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          if (_showSiteCapabilities) ...[
            const SizedBox(height: 10),
            _siteCapabilityChips(),
          ],
          if (_isRegister &&
              _siteStatus != null &&
              !_siteStatus!.registerEnabled) ...[
            const SizedBox(height: 10),
            Text(
              '该站点可能已关闭公开注册，提交后以站点返回为准。',
              style: TextStyle(
                color: dark ? const Color(0xFFFFB86B) : const Color(0xFFB05F00),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _accessCard(
    PlatformPreset preset,
    VaultStore store,
    bool dark,
    Color ink,
  ) {
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '登录方式',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ink,
            ),
          ),
          const SizedBox(height: 8),
          _segmentBar(
            dark: dark,
            embedded: true,
            children: [
              for (final item in _signMethodOptions(preset))
                _segmentTab(
                  selected: item.$1 == _SiteSignMethod.identity
                      ? _useIdentityMethod
                      : _signMethod == item.$1,
                  dark: dark,
                  onTap: () => setState(() {
                    if (item.$1 == _SiteSignMethod.identity) {
                      if (!_useIdentityMethod) {
                        _signMethod = _SiteSignMethod.identity;
                        _identityAccountId = null;
                      }
                    } else {
                      _signMethod = item.$1;
                      _identityAccountId = null;
                    }
                    _form.authMode = item.$1 == _SiteSignMethod.accessToken
                        ? AuthMode.accessToken
                        : AuthMode.password;
                  }),
                  child: Text(
                    item.$2,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color:
                          (item.$1 == _SiteSignMethod.identity
                              ? _useIdentityMethod
                              : _signMethod == item.$1)
                          ? ink
                          : ThemeDefine.kColorText,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _signMethodHint,
            style: const TextStyle(
              color: ThemeDefine.kColorText,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          if (_embedCredentials) ...[
            const SizedBox(height: 14),
            _credentialFields(preset, store),
          ],
        ],
      ),
    );
  }

  Widget _registerCard(PlatformPreset preset, VaultStore store) {
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '注册信息',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            '验证码会发到这个邮箱。收到后填入即可，不必打开站点网页。',
            style: TextStyle(
              color: ThemeDefine.kColorText,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          _credentialFields(preset, store),
        ],
      ),
    );
  }

  Widget _advancedCard(bool dark, Color ink) {
    return YuconCard(
      padding: EdgeInsets.fromLTRB(14, 2, 14, _showAdvanced ? 14 : 2),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Text(
                      '更多设置',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: ink,
                      ),
                    ),
                    const Spacer(),
                    if (!_showAdvanced)
                      const Text(
                        '备注 · 代理 · 充值比例',
                        style: TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 11,
                        ),
                      ),
                    const SizedBox(width: 4),
                    Icon(
                      _showAdvanced
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      size: 20,
                      color: ThemeDefine.kColorText,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showAdvanced) ...[
            LabeledField(
              label: '本地备注',
              child: TextField(
                controller: _alias,
                decoration: _boxInput(hint: '例如：主账号'),
              ),
            ),
            LabeledField(
              label: '站点名称',
              child: TextField(
                controller: _siteName,
                decoration: _boxInput(hint: '可留空，默认使用域名'),
              ),
            ),
            LabeledField(
              label: '其他调用地址',
              hint: '复制密钥时默认用站点地址。若还有别的调用地址，每行填一个。',
              child: TextField(
                controller: _apiUrls,
                minLines: 2,
                maxLines: 5,
                keyboardType: TextInputType.url,
                decoration: _boxInput(hint: '每行一个，可留空'),
              ),
            ),
            LabeledField(
              label: '充值比例',
              hint: '多少人民币等于 1 美元额度，默认 1。',
              child: TextField(
                controller: _topupRatio,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: _boxInput(hint: '默认 1'),
              ),
            ),
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '不计入总余额',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        '看板合计将忽略此账号，账号页仍显示自己的余额。',
                        style: TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 12,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _form.excludeFromTotalQuota,
                  onChanged: (value) =>
                      setState(() => _form.excludeFromTotalQuota = value),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _bottomBar({
    required bool dark,
    required double bottomPad,
    required String label,
    required bool busy,
  }) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(15, 12, 15, 12 + bottomPad),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          boxShadow: [
            BoxShadow(
              color: dark ? const Color(0x66000000) : const Color(0x14000000),
              blurRadius: 18,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: PrimaryButton(
          label: label,
          busy: busy,
          height: 46,
          onPressed: _save,
        ),
      ),
    );
  }

  bool get _showSiteCapabilities =>
      _siteStatus != null && _baseUrl.text.trim().isNotEmpty;

  Widget _siteCapabilityChips() {
    final status = _siteStatus;
    if (status == null) {
      return const SizedBox.shrink();
    }
    final chips = <(String, Color, Color)>[
      if (status.registerEnabled)
        ('可注册', const Color(0xFF168553), const Color(0xFFE7F7EF)),
      if (status.checkinEnabled)
        ('签到', const Color(0xFF3178DF), const Color(0xFFEDF4FF)),
      if (status.googleOAuth)
        ('Google', const Color(0xFF1F6FEB), const Color(0xFFEDF4FF)),
      if (status.githubOAuth)
        ('GitHub', const Color(0xFF25272B), const Color(0xFFEEF0F3)),
    ];
    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final chip in chips)
          StatusChip(label: chip.$1, color: chip.$2, background: chip.$3),
      ],
    );
  }

  void _onPickPlatform(PlatformPreset item) {
    setState(() {
      _userPickedPlatform = true;
      _form.platformType = item.type;
      if (!item.supportsAccessToken) {
        _form.authMode = AuthMode.password;
        _form.accessToken = '';
        if (_signMethod == _SiteSignMethod.accessToken) {
          _signMethod = _SiteSignMethod.password;
        }
      }
    });
    _scheduleProbe();
  }

  Widget _segmentBar({
    required bool dark,
    required List<Widget> children,
    bool embedded = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: embedded
            ? (dark ? const Color(0xFF232323) : const Color(0xFFEEEEF0))
            : (dark ? ThemeDefine.kColorDarkCard : ThemeDefine.kColorCard),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(children: children),
    );
  }

  Widget _segmentTab({
    required bool selected,
    required bool dark,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? (dark ? const Color(0xFF2C2C2E) : Colors.white)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: selected
                  ? const [
                      BoxShadow(
                        color: Color(0x14000000),
                        blurRadius: 6,
                        offset: Offset(0, 1),
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }

  InputDecoration _boxInput({String? hint, Widget? suffix}) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? const Color(0xFF232323) : const Color(0xFFEEEEF0);
    final line = dark ? ThemeDefine.kColorDarkLine : ThemeDefine.kColorLine;
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: fill,
      isDense: true,
      contentPadding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: ThemeDefine.kColorPrimary),
      ),
      suffixIcon: suffix,
      suffixIconConstraints: suffix == null
          ? null
          : const BoxConstraints(minWidth: 32, minHeight: 32),
    );
  }

  Widget _credentialFields(PlatformPreset preset, VaultStore store) {
    if (_signMethod == _SiteSignMethod.accessToken && !_isSub2) {
      return Column(
        children: [
          LabeledField(
            label: '访问令牌',
            requiredMark: !_isEditing,
            hint: _form.accessToken.trim().isEmpty
                ? '请填写个人设置里的访问令牌，不要填 sk- 开头的密钥。'
                : '已保存在本机，点右侧眼睛可查看。',
            child: TextField(
              controller: _accessToken,
              obscureText: !_showAccessToken,
              decoration: _boxInput(
                hint: '个人设置里的访问令牌',
                suffix: secretVisibilityButton(
                  visible: _showAccessToken,
                  onPressed: () =>
                      setState(() => _showAccessToken = !_showAccessToken),
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
              decoration: _boxInput(hint: '可留空，一般会自动识别'),
            ),
          ),
        ],
      );
    }
    if (_isRegister) {
      return Column(
        children: [
          LabeledField(
            label: '注册邮箱',
            requiredMark: true,
            child: TextField(
              controller: _username,
              keyboardType: TextInputType.emailAddress,
              decoration: _boxInput(hint: '用于接收验证码的邮箱'),
            ),
          ),
          LabeledField(
            label: '密码',
            requiredMark: true,
            last: true,
            hint: _passwordHint,
            child: TextField(
              controller: _password,
              obscureText: !_showPassword,
              autocorrect: false,
              decoration:
                  _boxInput(
                    hint: '自己填写，或点随机生成',
                    suffix: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: _fillRandomRegisterPassword,
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text('随机'),
                        ),
                        secretVisibilityButton(
                          visible: _showPassword,
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
                        ),
                      ],
                    ),
                  ).copyWith(
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 88,
                      minHeight: 32,
                    ),
                  ),
            ),
          ),
        ],
      );
    }
    return Column(
      children: [
        LabeledField(
          label: preset.identityLabel,
          requiredMark: !_isEditing,
          child: TextField(
            controller: _username,
            keyboardType: _isSub2
                ? TextInputType.emailAddress
                : TextInputType.text,
            decoration: _boxInput(hint: preset.identityPlaceholder),
          ),
        ),
        LabeledField(
          label: '密码',
          last: true,
          hint: _isEditing ? _passwordHint : null,
          child: TextField(
            controller: _password,
            obscureText: !_showPassword,
            decoration: _boxInput(
              hint: _isEditing ? '留空则沿用已保存的密码' : '登录成功后加密保存在本机',
              suffix: secretVisibilityButton(
                visible: _showPassword,
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<String?> _requestManualCode(String reason) async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        final dark = Theme.of(sheetContext).brightness == Brightness.dark;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: dark
                        ? ThemeDefine.kColorDarkLine
                        : ThemeDefine.kColorLine,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const Text(
                '填写验证码',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                reason,
                style: const TextStyle(
                  color: ThemeDefine.kColorText,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.text,
                autocorrect: false,
                maxLength: 8,
                decoration: _boxInput(hint: '邮箱验证码（4-8 位）')
                    .copyWith(counterText: ''),
              ),
              const SizedBox(height: 16),
              PrimaryButton(
                height: 46,
                label: '确认并继续注册',
                onPressed: () =>
                    Navigator.pop(sheetContext, controller.text.trim()),
              ),
              const SizedBox(height: 8),
              PrimaryButton(
                label: '取消注册',
                outlined: true,
                onPressed: () => Navigator.pop(sheetContext),
              ),
              SizedBox(height: MediaQuery.paddingOf(sheetContext).bottom),
            ],
          ),
        );
      },
    );
    controller.dispose();
    return (result == null || result.isEmpty) ? null : result;
  }

  void _dismissAuthProgress() {
    setState(() {
      _registerStage = null;
      _registerDetail = '';
      _registerError = null;
      _authFlow = null;
      _capturing = false;
      _saving = false;
    });
  }

  void _onRegisterProgress(SiteRegisterStage stage, String detail) {
    if (!mounted) {
      return;
    }
    setState(() {
      _registerStage = stage;
      _registerDetail = detail;
    });
  }

  List<(_SiteSignMethod, String, String)> _signMethodOptions(
    PlatformPreset preset,
  ) {
    return [
      (_SiteSignMethod.password, '密码', '调用接口自动登录'),
      (_SiteSignMethod.identity, '身份', '用已记住的 Google / GitHub'),
      if (!_isSub2 && preset.supportsAccessToken)
        (_SiteSignMethod.accessToken, '令牌', '从个人设置粘贴'),
    ];
  }

  List<Widget> _identityGroupCards(VaultStore store, bool dark) {
    return [
      for (final provider in [googleIdentityProvider, githubIdentityProvider])
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _identityCard(store, provider, dark),
        ),
    ];
  }

  Widget _identityCard(VaultStore store, String provider, bool dark) {
    final options = _identityOptionsFor(store, provider);
    return YuconCard(
      padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(
              children: [
                provider == githubIdentityProvider
                    ? const IdentityBrandIcon.github(size: 22)
                    : const IdentityBrandIcon.google(size: 22),
                const SizedBox(width: 8),
                Text(
                  identityGroupTitle(provider),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (options.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '还没有记住的${identityLoginTitle(provider)}',
                  style: const TextStyle(
                    color: ThemeDefine.kColorText,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            for (final option in options) _identityRow(option, dark),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const IdentityScreen()),
                );
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                child: Row(
                  children: [
                    const Icon(
                      Icons.add_rounded,
                      size: 18,
                      color: ThemeDefine.kColorPrimary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '添加${identityLoginTitle(provider)}',
                      style: const TextStyle(
                        color: ThemeDefine.kColorPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _identityRow(_IdentityOption option, bool dark) {
    final selected =
        _useIdentity && option.sessionId == (_identityAccountId ?? '');
    final checking = option.sessionId == (_checkingIdentityId ?? '');
    final fill = selected
        ? (dark ? const Color(0x22FA2C19) : ThemeDefine.kColorSoft)
        : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => unawaited(_connectWithIdentity(option)),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        checking
                            ? '正在确认登录是否有效'
                            : (option.connected ? '已记住，可直接使用' : '尚未登录，选中后会先检查'),
                        style: const TextStyle(
                          color: ThemeDefine.kColorText,
                          fontSize: 12,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (checking)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    selected
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    size: 20,
                    color: selected
                        ? ThemeDefine.kColorPrimary
                        : ThemeDefine.kColorText,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<_IdentityOption> _identityOptionsFor(VaultStore store, String provider) {
    final method = provider == githubIdentityProvider
        ? _SiteSignMethod.github
        : _SiteSignMethod.google;
    final options = <_IdentityOption>[];
    final logins = store.identityLoginsFor(provider);
    if (logins.isEmpty) {
      if (store.identityWindowConnected(provider)) {
        options.add(
          _IdentityOption(
            provider: provider,
            method: method,
            sessionId: store.identitySessionKey(provider),
            label: store.identityWindowLabel(provider),
            connected: true,
          ),
        );
      }
      return options;
    }
    for (final login in logins) {
      options.add(
        _IdentityOption(
          provider: provider,
          method: method,
          sessionId: login.id,
          label: login.label,
          connected: store.identityWindowConnected(
            provider,
            accountId: login.id,
          ),
        ),
      );
    }
    return options;
  }

  Future<void> _connectWithIdentity(_IdentityOption option) async {
    final store = context.read<VaultStore>();
    setState(() {
      _signMethod = option.method;
      _identityAccountId = option.sessionId;
      _form.authMode = AuthMode.password;
    });
    await store.selectIdentityLogin(option.provider, option.sessionId);
  }
}

class _IdentityOption {
  const _IdentityOption({
    required this.provider,
    required this.method,
    required this.sessionId,
    required this.label,
    required this.connected,
  });

  final String provider;
  final _SiteSignMethod method;
  final String sessionId;
  final String label;
  final bool connected;
}
