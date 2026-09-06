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

class GoogleIdentityScreen extends StatefulWidget {
  const GoogleIdentityScreen({super.key, this.login});

  final IdentityLoginAccount? login;

  @override
  State<GoogleIdentityScreen> createState() => _GoogleIdentityScreenState();
}

class _GoogleIdentityScreenState extends State<GoogleIdentityScreen> {
  late final WebViewController _controller;
  late final VaultStore _store;
  late String _sessionId;
  IdentityLoginAccount? _login;
  final _cookieManager = WebViewCookieManager();
  Timer? _poller;
  bool _saving = false;
  bool _loggedIn = false;
  bool _captcha = false;
  bool _cookieError = false;
  bool _retriedWithoutCookies = false;
  bool _notifiedSave = false;
  DateTime? _lastSaveAttempt;
  String _currentUrl = googleIdentityHomeUrl;

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
      googleIdentityProvider,
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
      _store.identityWindowConnected(googleIdentityProvider, accountId: _sessionId);

  Future<void> _start() async {
    final login = _login;
    if (login != null) {
      await _store.selectIdentityLogin(googleIdentityProvider, login.id);
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
              _syncUrl(change.url!);
            }
          },
        ),
      );
    await prepareAuthWebView(_controller, _cookieManager);
    await scrubIdentityWebViewCookies(googleIdentityProvider);
    await restoreWebIdentityCookies(_store.identitySessionFor(_sessionId));
    await _controller.loadRequest(Uri.parse(googleIdentityHomeUrl));
    if (!mounted) {
      return;
    }
    _poller = Timer.periodic(const Duration(milliseconds: 500), (_) => unawaited(_onPage()));
  }

  void _syncUrl(String url) {
    if (url.isEmpty) {
      return;
    }
    final loggedIn = looksLikeGoogleLoggedIn(url) && !looksLikeGoogleCookieError(url);
    final captcha = looksLikeGoogleCaptcha(url);
    final cookieError = looksLikeGoogleCookieError(url) || _cookieError;
    if (!mounted) {
      _currentUrl = url;
      _loggedIn = loggedIn;
      _captcha = captcha;
      _cookieError = cookieError;
      return;
    }
    setState(() {
      _currentUrl = url;
      _loggedIn = loggedIn;
      _captcha = captcha;
      _cookieError = cookieError;
    });
  }

  Future<void> _onPage() async {
    final url = await _controller.currentUrl();
    if (!mounted) {
      return;
    }
    if (url != null && url.isNotEmpty) {
      _syncUrl(url);
    }
    if (shouldAutofillIdentityLogin(googleIdentityProvider, _currentUrl) && !_cookieError) {
      await fillIdentityLogin(_controller, _fillLogin);
    }
    if (!mounted) {
      return;
    }
    if (await _pageHasCookieError()) {
      if (mounted && !_cookieError) {
        setState(() => _cookieError = true);
      }
      await _retryWithoutSavedCookies();
      return;
    }
    if (!_loggedIn || _captcha || _cookieError || _saving) {
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

  Future<bool> _pageHasCookieError() async {
    if (looksLikeGoogleCookieError(_currentUrl)) {
      return true;
    }
    try {
      final raw = await _controller.runJavaScriptReturningResult(_cookieErrorScript);
      final text = raw.toString().trim().replaceAll('"', '').replaceAll("'", '');
      return text == '1' || text == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<void> _retryWithoutSavedCookies() async {
    if (_retriedWithoutCookies) {
      return;
    }
    _retriedWithoutCookies = true;
    await scrubIdentityWebViewCookies(googleIdentityProvider);
    if (!mounted) {
      return;
    }
    await _controller.loadRequest(Uri.parse(googleIdentityHomeUrl));
  }

  String get _subtitle {
    if (_saving) {
      return '已登录，正在保存';
    }
    if (_cookieError) {
      return 'Cookie 被拦截，正在改用干净会话重试';
    }
    if (_captcha) {
      return '出现验证码，请在页面里完成';
    }
    if (_loggedIn) {
      return '已记住，可留在这个窗口';
    }
    if (looksLikeGoogleSignIn(_currentUrl)) {
      return '请在页面里登录，验证码需手动完成';
    }
    return '正在检查已保存的 Google 登录';
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
      final email = await _readEmail();
      final snapshot = await captureGoogleIdentity(email: email ?? '');
      if (!snapshot.isConnected) {
        _saving = false;
        if (mounted) {
          if (notifyEmpty) {
            _store.notify('还没有拿到 Google 登录状态', FeedbackType.warning);
          }
          setState(() {});
        }
        return;
      }
      await _store.rememberGoogleIdentity(snapshot, accountId: _sessionId);
      _saving = false;
      if (mounted) {
        if (notifySuccess && !_notifiedSave) {
          _notifiedSave = true;
          _store.notify('已记住 Google 登录');
        }
        setState(() {
          _loggedIn = true;
        });
      }
    } catch (error) {
      _saving = false;
      if (mounted) {
        _store.notify(userFacingError(error, '保存 Google 登录失败'), FeedbackType.warning);
        setState(() {});
      }
    }
  }

  Future<void> _persistOnLeave() async {
    try {
      final snapshot = await captureGoogleIdentity(
        email: _store.identitySessionFor(_sessionId)?.email ?? '',
      );
      if (snapshot.isConnected) {
        await _store.rememberGoogleIdentity(snapshot, accountId: _sessionId);
      }
    } catch (_) {}
    await applyWebViewProxy(null);
  }

  Future<String?> _readEmail() async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(_emailScript);
      return parseGoogleEmailFromJs(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _disconnect() async {
    await _store.forgetGoogleIdentity(accountId: _sessionId);
    await scrubIdentityWebViewCookies(googleIdentityProvider);
    if (!mounted) {
      return;
    }
    _notifiedSave = false;
    _retriedWithoutCookies = false;
    _lastSaveAttempt = null;
    setState(() {
      _loggedIn = false;
      _cookieError = false;
      _captcha = false;
    });
    await _controller.loadRequest(Uri.parse(googleIdentityHomeUrl));
    _store.notify('已断开 Google 登录', FeedbackType.text);
  }

  Future<void> _editLogin() async {
    final next = await showIdentityLoginEditor(
      context: context,
      provider: googleIdentityProvider,
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
          title: identityWindowTitle(googleIdentityProvider, login: _fillLogin),
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

const _emailScript = r'''
(function(){
  try {
    var attr = document.documentElement.getAttribute("data-email") || "";
    if (attr && attr.indexOf("@") >= 0) return attr;
  } catch (e) {}
  try {
    var nodes = document.querySelectorAll("[data-email], [aria-label*='@']");
    for (var i = 0; i < nodes.length; i++) {
      var text = nodes[i].getAttribute("data-email") || nodes[i].getAttribute("aria-label") || "";
      var found = String(text).match(/[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}/i);
      if (found) return found[0];
    }
  } catch (e) {}
  try {
    var html = document.documentElement.innerHTML || "";
    var match = html.match(/[A-Z0-9._%+\-]+@(?:gmail|googlemail)\.com/i);
    if (match) return match[0];
  } catch (e) {}
  return "";
})();
''';

const _cookieErrorScript = r'''
(function(){
  try {
    var t = (document.body && document.body.innerText) || "";
    if (t.indexOf("Cookie 设置存在问题") >= 0) return "1";
    if (t.indexOf("problem with your cookie settings") >= 0) return "1";
  } catch (e) {}
  return "0";
})();
''';
