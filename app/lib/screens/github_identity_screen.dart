import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/identity/web_identity_io.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/identity_login_sheet.dart';
import 'package:vault/screens/widgets/ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

class GitHubIdentityScreen extends StatefulWidget {
  const GitHubIdentityScreen({super.key, this.login});

  final IdentityLoginAccount? login;

  @override
  State<GitHubIdentityScreen> createState() => _GitHubIdentityScreenState();
}

class _GitHubIdentityScreenState extends State<GitHubIdentityScreen> {
  late final WebViewController _controller;
  late final VaultStore _store;
  late String _sessionId;
  IdentityLoginAccount? _login;
  final _cookieManager = WebViewCookieManager();
  Timer? _poller;
  bool _saving = false;
  bool _loggedIn = false;
  bool _captcha = false;
  bool _notifiedSave = false;
  DateTime? _lastSaveAttempt;
  String _currentUrl = githubIdentityHomeUrl;

  @override
  void initState() {
    super.initState();
    _store = context.read<VaultStore>();
    _bindLogin(widget.login);
    _controller = WebViewController();
    unawaited(_start());
  }

  @override
  void dispose() {
    _poller?.cancel();
    unawaited(_persistOnLeave());
    super.dispose();
  }

  void _bindLogin(IdentityLoginAccount? login) {
    _login = login;
    _sessionId = _store.identitySessionKey(
      githubIdentityProvider,
      accountId: login?.id,
    );
  }

  IdentityLoginAccount? get _fillLogin {
    final id = _login?.id ?? '';
    if (id.isEmpty) {
      return _login;
    }
    for (final account in _store.identityLogins) {
      if (account.id == id) {
        return account;
      }
    }
    return _login;
  }

  bool get _connected =>
      _store.identityWindowConnected(githubIdentityProvider, accountId: _sessionId);

  Future<void> _start() async {
    final login = _login;
    if (login != null) {
      await _store.selectIdentityLogin(githubIdentityProvider, login.id);
    }
    await applyWebViewProxy(_store.resolvedProxy(_store.settings.networkProxy));
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ThemeDefine.kColorPage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => unawaited(_onPage()),
          onUrlChange: (change) {
            if (change.url != null) {
              unawaited(_syncUrl(change.url!));
            }
          },
        ),
      );
    await prepareAuthWebView(_controller, _cookieManager);
    await scrubIdentityWebViewCookies(githubIdentityProvider);
    await restoreWebIdentityCookies(_store.identitySessionFor(_sessionId));
    await _controller.loadRequest(Uri.parse(githubIdentityHomeUrl));
    if (!mounted) {
      return;
    }
    _poller = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_onPage()));
  }

  Future<void> _syncUrl(String url, {String? login}) async {
    if (url.isEmpty) {
      return;
    }
    final captcha = looksLikeGitHubCaptcha(url);
    final loggedIn = login != null || (looksLikeGitHubLoggedIn(url) && !captcha);
    if (!mounted) {
      _currentUrl = url;
      _loggedIn = loggedIn;
      _captcha = captcha;
      return;
    }
    setState(() {
      _currentUrl = url;
      _loggedIn = loggedIn;
      _captcha = captcha;
    });
  }

  Future<void> _onPage() async {
    final url = await _controller.currentUrl();
    final login = await _readLogin();
    if (!mounted) {
      return;
    }
    if (url != null && url.isNotEmpty) {
      await _syncUrl(url, login: login);
    }
    if (!mounted) {
      return;
    }
    if (shouldAutofillIdentityLogin(githubIdentityProvider, url ?? _currentUrl)) {
      await fillIdentityLogin(_controller, _fillLogin);
    }
    if (!_loggedIn || _captcha || _saving) {
      return;
    }
    final last = _lastSaveAttempt;
    final already = _connected;
    final interval = already ? const Duration(seconds: 8) : const Duration(seconds: 2);
    if (last != null && DateTime.now().difference(last) <= interval) {
      return;
    }
    await _save(notifySuccess: !already);
  }

  String get _subtitle {
    if (_saving) {
      return '已登录，正在保存';
    }
    if (_captcha) {
      return '出现验证码，请在页面里完成';
    }
    if (_loggedIn) {
      return '已记住，可留在这个窗口';
    }
    if (looksLikeGitHubSignIn(_currentUrl)) {
      return '请在页面里登录，验证码和两步验证需手动完成';
    }
    return '正在检查已保存的 GitHub 登录';
  }

  Future<void> _save({
    bool notifyEmpty = false,
    bool notifySuccess = true,
  }) async {
    if (_saving) {
      return;
    }
    _saving = true;
    _lastSaveAttempt = DateTime.now();
    if (mounted) {
      setState(() {});
    }
    try {
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final login = await _readLogin();
      final snapshot = await captureGitHubIdentity(email: login ?? '');
      if (!snapshot.isConnected) {
        _saving = false;
        if (mounted) {
          if (notifyEmpty) {
            _store.notify('还没有拿到 GitHub 登录状态', FeedbackType.warning);
          }
          setState(() {});
        }
        return;
      }
      await _store.rememberGitHubIdentity(snapshot, accountId: _sessionId);
      _saving = false;
      if (mounted) {
        if (notifySuccess && !_notifiedSave) {
          _notifiedSave = true;
          _store.notify('已记住 GitHub 登录');
        }
        setState(() {
          _loggedIn = true;
        });
      }
    } catch (error) {
      _saving = false;
      if (mounted) {
        _store.notify(userFacingError(error, '保存 GitHub 登录失败'), FeedbackType.warning);
        setState(() {});
      }
    }
  }

  Future<void> _persistOnLeave() async {
    try {
      final snapshot = await captureGitHubIdentity(
        email: _store.identitySessionFor(_sessionId)?.email ?? '',
      );
      if (snapshot.isConnected) {
        await _store.rememberGitHubIdentity(snapshot, accountId: _sessionId);
      }
    } catch (_) {}
    await applyWebViewProxy(null);
  }

  Future<String?> _readLogin() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(_loginScript);
      return parseGitHubLoginFromJs(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _disconnect() async {
    await _store.forgetGitHubIdentity(accountId: _sessionId);
    await scrubIdentityWebViewCookies(githubIdentityProvider);
    if (!mounted) {
      return;
    }
    _notifiedSave = false;
    _lastSaveAttempt = null;
    setState(() {
      _loggedIn = false;
      _captcha = false;
    });
    await _controller.loadRequest(Uri.parse(githubIdentityHomeUrl));
    _store.notify('已断开 GitHub 登录', FeedbackType.text);
  }

  Future<void> _editLogin() async {
    final next = await showIdentityLoginEditor(
      context: context,
      provider: githubIdentityProvider,
      account: _login,
    );
    if (!mounted) {
      return;
    }
    if (next == null && _login != null) {
      Navigator.of(context).pop(false);
      return;
    }
    if (next != null) {
      setState(() => _bindLogin(next));
    }
    await fillIdentityLogin(_controller, _fillLogin);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<VaultStore>();
    return SecureScope(
      child: Scaffold(
        appBar: YuconAppBar(
          title: identityWindowTitle(githubIdentityProvider, login: _fillLogin),
          subtitle: _subtitle,
          actions: [
            HeaderTextAction(
              label: '账号',
              onPressed: () => unawaited(_editLogin()),
            ),
            if (_connected && !_saving)
              HeaderTextAction(label: '断开', onPressed: () => unawaited(_disconnect())),
            if (!_saving)
              HeaderTextAction(
                label: '保存',
                onPressed: () => unawaited(_save(notifyEmpty: true)),
              ),
          ],
        ),
        body: authWebView(_controller),
      ),
    );
  }
}

const _loginScript = r'''
(function(){
  try {
    var login = document.querySelector('meta[name="user-login"]');
    if (login && login.content) return login.content;
  } catch (e) {}
  try {
    var actor = document.querySelector('meta[name="octolytics-actor-login"]');
    if (actor && actor.content) return actor.content;
  } catch (e) {}
  return "";
})();
''';
