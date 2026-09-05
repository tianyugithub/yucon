import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/privacy/screen_privacy.dart';
import 'package:vault/screens/theme_define.dart';
import 'package:vault/screens/widgets/ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

class SiteSession {
  const SiteSession({
    required this.accessToken,
    this.refreshToken = '',
    this.cookies = '',
    this.userId = '',
    this.username = '',
  });

  final String accessToken;
  final String refreshToken;
  final String cookies;
  final String userId;
  final String username;

  bool get hasAuth => accessToken.trim().isNotEmpty;

  SiteSession copyWith({
    String? accessToken,
    String? refreshToken,
    String? cookies,
    String? userId,
    String? username,
  }) {
    return SiteSession(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      cookies: cookies ?? this.cookies,
      userId: userId ?? this.userId,
      username: username ?? this.username,
    );
  }
}

class _ParsedCapture {
  const _ParsedCapture({
    required this.session,
    required this.loggedIn,
    this.pageLoggedIn = false,
  });

  final SiteSession session;
  final bool loggedIn;
  final bool pageLoggedIn;
}

class SiteNetworkBlocked {
  const SiteNetworkBlocked();
}

class SiteLoginScreen extends StatefulWidget {
  const SiteLoginScreen({
    super.key,
    required this.loginUrl,
    required this.kind,
    this.startUrl = '',
    this.email = '',
    this.password = '',
  });

  final String loginUrl;
  final String startUrl;
  final PlatformType kind;
  final String email;
  final String password;

  @override
  State<SiteLoginScreen> createState() => _SiteLoginScreenState();
}

class _SiteLoginScreenState extends State<SiteLoginScreen> {
  late final WebViewController _controller;
  final _cookieManager = WebViewCookieManager();
  Timer? _poller;
  bool _finished = false;
  bool _primed = false;
  bool _networkBlocked = false;
  bool _looksLoggedIn = false;

  bool get _isSub2 => widget.kind == PlatformType.sub2api;

  String get _siteHost {
    try {
      final host = Uri.parse(widget.loginUrl).host.trim();
      return host.isEmpty ? '这个网站' : host;
    } catch (_) {
      return '这个网站';
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();
    unawaited(_start());
  }

  Future<void> _start() async {
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(ThemeDefine.kColorPage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => unawaited(_injectWatch()),
          onPageFinished: (_) => unawaited(_onPageFinished()),
          onUrlChange: (change) => unawaited(_onUrlChanged(change.url)),
          onHttpError: (error) {
            if (error.response?.statusCode == 403) {
              unawaited(_detectNetworkBlock());
            }
          },
        ),
      );
    await _controller.addJavaScriptChannel(
      'YuconHost',
      onMessageReceived: (message) {
        if (message.message == 'network-blocked') {
          _markNetworkBlocked();
          return;
        }
        unawaited(_acceptRawSession(message.message));
      },
    );
    await _controller.loadRequest(Uri.parse(_initialUrl));
    if (!mounted) {
      return;
    }
    _poller = Timer.periodic(const Duration(milliseconds: 400), (_) => unawaited(_poll()));
  }

  String get _initialUrl {
    final start = widget.startUrl.trim();
    return start.isEmpty ? widget.loginUrl : start;
  }

  Future<void> _injectWatch() async {
    try {
      await _controller.runJavaScript(_watchScript());
    } catch (_) {}
  }

  Future<void> _onPageFinished() async {
    await _enableAndroidCookies();
    final url = await _controller.currentUrl();
    final current = url ?? widget.loginUrl;
    if (!_looksLoggedIn && !_isAppPath(current)) {
      await _detectNetworkBlock();
    }
    if (_networkBlocked || _finished) {
      return;
    }
    if (!_primed) {
      _primed = true;
      await _controller.runJavaScript(_primeScript());
    }
    if (_isAuthPath(current) && !_looksLoggedIn) {
      await _controller.runJavaScript(_assistScript());
    }
    await _controller.runJavaScript(_watchScript());
    await _pollSession();
  }

  Future<void> _onUrlChanged(String? url) async {
    if (_finished || _networkBlocked || url == null || url.isEmpty) {
      return;
    }
    if (_isAppPath(url) && mounted && !_looksLoggedIn) {
      setState(() => _looksLoggedIn = true);
    }
    await _controller.runJavaScript(_watchScript());
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await _pollSession();
  }

  @override
  void dispose() {
    _poller?.cancel();
    super.dispose();
  }

  Future<void> _enableAndroidCookies() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    final platform = _cookieManager.platform;
    final controller = _controller.platform;
    if (platform is AndroidWebViewCookieManager && controller is AndroidWebViewController) {
      try {
        await platform.setAcceptThirdPartyCookies(controller, true);
      } catch (_) {}
    }
  }

  bool _isAuthPath(String url) {
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return path.contains('/login') ||
        path.contains('/sign-in') ||
        path.contains('/signin') ||
        path.contains('/sign-up') ||
        path.contains('/register') ||
        path.contains('/reset') ||
        path.contains('/forgot') ||
        path.contains('/oauth') ||
        path.contains('/2fa') ||
        path.contains('/mfa') ||
        path.contains('/turnstile');
  }

  bool _looksLikeSessionCookie(String cookies) {
    return RegExp(
      r'(?:^|;\s*)(?:session(?:id)?|new[-_]?api[^=]*|__host-session|__secure-session|jwt|access_token)\s*=',
      caseSensitive: false,
    ).hasMatch(cookies);
  }

  bool _isBearerToken(String token) {
    final value = token.trim();
    if (value.isEmpty || value.startsWith(cookieAuthPrefix) || value.startsWith('sk-')) {
      return false;
    }
    return value.length >= 16;
  }

  bool _isAppPath(String url) {
    if (_isAuthPath(url)) {
      return false;
    }
    final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
    return RegExp(
      r'^/(console|panel|dashboard|app|admin|tokens?|channel|logs?|topup|wallet|personal|settings?|playground)(/|$)',
    ).hasMatch(path);
  }

  Future<String> _webViewCookies() async {
    final url = await _controller.currentUrl() ?? widget.loginUrl;
    final native = mergeCookies([
      await readWebViewCookieHeader(url),
      await readWebViewCookieHeader(widget.loginUrl),
      await readWebViewCookieHeader(_initialUrl),
      await readSiteCookieHeader(widget.loginUrl),
    ]);
    if (native.isNotEmpty) {
      return native;
    }
    try {
      final cookies = await _cookieManager.getCookies(domain: Uri.parse(url));
      return cookies
          .where((cookie) => cookie.name.trim().isNotEmpty)
          .map((cookie) => '${cookie.name}=${cookie.value}')
          .join('; ');
    } catch (_) {
      return '';
    }
  }

  Future<void> _detectNetworkBlock() async {
    if (_finished || _networkBlocked || !mounted) {
      return;
    }
    try {
      final title = await _controller.getTitle();
      if (looksLikeNetworkBlockPage(title ?? '')) {
        _markNetworkBlocked();
        return;
      }
    } catch (_) {}
    try {
      final raw = await _controller.runJavaScriptReturningResult(_blockCheckScript());
      if (_jsTruthy(raw)) {
        _markNetworkBlocked();
      }
    } catch (_) {}
  }

  bool _jsTruthy(Object? value) {
    if (value == true || value == 1) {
      return true;
    }
    final text = value?.toString().toLowerCase().trim() ?? '';
    return text == 'true' || text == '"true"' || text == '1' || text == '"1"' || text == '1.0';
  }

  void _markNetworkBlocked() {
    if (_finished || _networkBlocked) {
      return;
    }
    _networkBlocked = true;
    _poller?.cancel();
    if (mounted) {
      setState(() {});
    }
  }

  void _leaveBlocked() {
    if (_finished) {
      return;
    }
    _finished = true;
    _poller?.cancel();
    Navigator.of(context).pop(const SiteNetworkBlocked());
  }

  Future<void> _useCurrentLogin() async {
    try {
      await _controller.runJavaScript(
        '(function(){window.__yuconRefreshAgain=true;window.__yuconRefreshCount=0;})();',
      );
    } catch (_) {}
    await _controller.runJavaScript(_watchScript());
    for (final wait in [400, 700, 1100]) {
      await Future<void>.delayed(Duration(milliseconds: wait));
      if (!mounted || _finished) {
        return;
      }
      await _pollSession();
      if (_finished) {
        return;
      }
    }
    if (!mounted || _finished) {
      return;
    }
    final cookies = await _webViewCookies();
    if (!mounted || _finished) {
      return;
    }
    final url = await _controller.currentUrl() ?? '';
    if (!_isAuthPath(url) && cookies.isNotEmpty && _looksLikeSessionCookie(cookies)) {
      _finish(
        SiteSession(
          accessToken: asCookieAuth(cookies),
          cookies: cookies,
        ),
      );
      return;
    }
    if (!mounted || _finished) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('还没取到登录凭证。请等控制台完全打开后再点一次「使用当前登录」')),
    );
  }

  Future<void> _poll() async {
    if (_finished || _networkBlocked || !mounted) {
      return;
    }
    final url = await _controller.currentUrl();
    if (_isAuthPath(url ?? widget.loginUrl)) {
      await _detectNetworkBlock();
    }
    if (_finished || _networkBlocked || !mounted) {
      return;
    }
    if (_isAuthPath(url ?? widget.loginUrl) && !_looksLoggedIn) {
      await _controller.runJavaScript(_assistScript());
    }
    await _controller.runJavaScript(_watchScript());
    await _pollSession();
  }

  Future<void> _pollSession() async {
    if (_finished || _networkBlocked || !mounted) {
      return;
    }
    try {
      final raw = await _controller.runJavaScriptReturningResult(_sessionScript());
      await _acceptRawSession(raw);
    } catch (_) {}
  }

  Future<void> _acceptRawSession(Object? raw) async {
    final parsed = _parseSession(raw);
    if (parsed == null || _finished || _networkBlocked || !mounted) {
      return;
    }
    if ((parsed.loggedIn || parsed.pageLoggedIn) && !_looksLoggedIn) {
      setState(() => _looksLoggedIn = true);
    }
    String cookies = '';
    try {
      cookies = mergeCookies([parsed.session.cookies, await _webViewCookies()]);
    } catch (_) {
      cookies = parsed.session.cookies;
    }
    if (_isSub2) {
      if (parsed.session.accessToken.isEmpty) {
        return;
      }
      _finish(parsed.session.copyWith(cookies: cookies));
      return;
    }
    final url = await _controller.currentUrl() ?? '';
    final bearer = _isBearerToken(parsed.session.accessToken) ? parsed.session.accessToken.trim() : '';
    if (bearer.isNotEmpty) {
      _finish(parsed.session.copyWith(accessToken: bearer, cookies: cookies));
      return;
    }
    if (_isAuthPath(url)) {
      return;
    }
    if (parsed.session.userId.isEmpty || !_looksLikeSessionCookie(cookies)) {
      return;
    }
    _finish(
      parsed.session.copyWith(
        accessToken: asCookieAuth(cookies),
        cookies: cookies,
      ),
    );
  }

  _ParsedCapture? _parseSession(Object? value) {
    if (value == null || value == 'null') {
      return null;
    }
    Object? decoded = value;
    if (decoded is String) {
      if (decoded == 'null' || decoded.isEmpty) {
        return null;
      }
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return null;
      }
    }
    if (decoded is! Map) {
      return null;
    }
    var accessToken = decoded['accessToken']?.toString().trim() ?? '';
    var cookies = decoded['cookies']?.toString() ?? '';
    var userId = decoded['userId']?.toString() ?? '';
    var username = decoded['username']?.toString() ?? '';
    final loggedIn = decoded['loggedIn'] == true ||
        decoded['loggedIn'] == 1 ||
        decoded['loggedIn']?.toString() == 'true';
    final pageLoggedIn = decoded['pageLoggedIn'] == true ||
        decoded['pageLoggedIn'] == 1 ||
        decoded['pageLoggedIn']?.toString() == 'true';
    if (accessToken == 'null' || accessToken == 'undefined') {
      accessToken = '';
    }
    if (userId == 'null' || userId == 'undefined' || userId == '0') {
      userId = '';
    }
    if (username == 'null' || username == 'undefined') {
      username = '';
    }
    if (_isSub2 && accessToken.isEmpty) {
      return null;
    }
    if (!_isSub2 && accessToken.isEmpty && userId.isEmpty && !loggedIn && !pageLoggedIn) {
      return null;
    }
    return _ParsedCapture(
      session: SiteSession(
        accessToken: accessToken,
        refreshToken: decoded['refreshToken']?.toString() ?? '',
        cookies: cookies,
        userId: userId,
        username: username,
      ),
      loggedIn: loggedIn || accessToken.isNotEmpty || userId.isNotEmpty,
      pageLoggedIn: pageLoggedIn,
    );
  }

  void _finish(SiteSession session) {
    if (_finished || !session.hasAuth) {
      return;
    }
    _finished = true;
    _poller?.cancel();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop(session);
  }

  String _blockCheckScript() {
    return r'''
(function(){
  function hay(doc){
    if(!doc)return "";
    var title=doc.title||"";
    var text=(doc.body&&(doc.body.innerText||doc.body.textContent))||"";
    var html=(doc.documentElement&&doc.documentElement.innerHTML)||"";
    return (title+" "+text+" "+html).toLowerCase();
  }
  function blocked(doc){
    var all=hay(doc);
    if(all.indexOf("sorry, you have been blocked")>=0)return true;
    if(all.indexOf("you are unable to access")>=0)return true;
    if(all.indexOf("why have i been blocked")>=0)return true;
    if(all.indexOf("blocked_why")>=0)return true;
    if(all.indexOf("error 1020")>=0)return true;
    var h1=doc&&doc.querySelector&&doc.querySelector("h1");
    if(h1&&/you have been blocked/i.test(h1.textContent||""))return true;
    return false;
  }
  var hit=blocked(document);
  if(!hit){
    var frames=document.querySelectorAll("iframe");
    for(var i=0;i<frames.length;i++){
      try{if(blocked(frames[i].contentDocument)){hit=true;break;}}catch(e){}
    }
  }
  if(hit){
    try{YuconHost.postMessage("network-blocked");}catch(e){}
    return 1;
  }
  return 0;
})()
''';
  }

  String _primeScript() {
    if (_isSub2) {
      return '(function(){'
          'var wanted=${jsonEncode(widget.email)};'
          'function readUser(){try{return JSON.parse(localStorage.getItem("auth_user")||"null")}catch(e){return null}}'
          'var token=localStorage.getItem("auth_token");'
          'var user=readUser();'
          'var current=user&&user.email?String(user.email):"";'
          'if(token&&wanted&&current&&current.toLowerCase()!==wanted.toLowerCase()){'
          'localStorage.removeItem("auth_token");'
          'localStorage.removeItem("refresh_token");'
          'localStorage.removeItem("auth_user");'
          'localStorage.removeItem("token_expires_at");'
          'location.replace(${jsonEncode(widget.loginUrl)});'
          '}'
          '})();';
    }
    return '(function(){})();';
  }

  String _sessionScript() {
    if (_isSub2) {
      return r'''
(function(){
  var token=localStorage.getItem("auth_token");
  if(!token)return JSON.stringify(null);
  var user=null;try{user=JSON.parse(localStorage.getItem("auth_user")||"null")}catch(e){}
  var current=user&&user.email?String(user.email):"";
  return JSON.stringify({accessToken:token,refreshToken:localStorage.getItem("refresh_token")||"",cookies:document.cookie||"",username:current,userId:user&&user.id!=null?String(user.id):"",loggedIn:true});
})()
''';
    }
    return '''
(function(){
  try{
    if(window.__yuconScan)return JSON.stringify(window.__yuconScan());
  }catch(e){}
  return JSON.stringify(window.__yuconCapture||null);
})()
''';
  }

  String _watchScript() {
    if (_isSub2) {
      return r'''
(function(){
  var token=localStorage.getItem("auth_token");
  if(!token)return;
  var user=null;try{user=JSON.parse(localStorage.getItem("auth_user")||"null")}catch(e){}
  var current=user&&user.email?String(user.email):"";
  var session={accessToken:token,refreshToken:localStorage.getItem("refresh_token")||"",cookies:document.cookie||"",username:current,userId:user&&user.id!=null?String(user.id):"",loggedIn:true};
  window.__yuconCapture=session;
  try{YuconHost.postMessage(JSON.stringify(session));}catch(e){}
})();
''';
    }
    return r'''
(function(){
  function nameOf(user){
    if(!user||typeof user!=="object")return "";
    return String(user.username||user.display_name||user.displayName||user.email||user.name||"");
  }
  function pickToken(data){
    if(!data)return "";
    if(typeof data==="string")return looksAccessToken(data);
    var fromAccess=looksAccessToken(data.access_token);
    if(fromAccess)return fromAccess;
    var fromToken=looksAccessToken(data.token);
    if(fromToken)return fromToken;
    if(data.user&&typeof data.user==="object"){
      var nested=pickToken(data.user);
      if(nested)return nested;
    }
    if(data.data&&typeof data.data==="object"){
      var fromData=pickToken(data.data);
      if(fromData)return fromData;
    }
    return "";
  }
  function looksAccessToken(value){
    var text=String(value||"").trim();
    if(!text||text.length<16)return "";
    if(/^sk-/i.test(text))return "";
    if(/^cookie:/i.test(text))return "";
    return text;
  }
  function asUser(obj){
    if(!obj||typeof obj!=="object")return null;
    if(obj.state&&typeof obj.state==="object"){
      var nested=asUser(obj.state.user)||asUser(obj.state);
      if(nested)return nested;
    }
    if(obj.user&&typeof obj.user==="object"){
      var inner=asUser(obj.user);
      if(inner)return inner;
    }
    if(obj.data&&typeof obj.data==="object"){
      var dataUser=asUser(obj.data);
      if(dataUser)return dataUser;
    }
    var id=obj.id;
    if(id==null||id===""||id===0||id==="0")return null;
    if(!(obj.username||obj.display_name||obj.displayName||obj.email))return null;
    return obj;
  }
  function readUser(){
    var keys=["user","userInfo","auth_user","currentUser"];
    var stores=[];
    try{stores.push(localStorage);}catch(e){}
    try{stores.push(sessionStorage);}catch(e){}
    for(var s=0;s<stores.length;s++){
      var store=stores[s];
      for(var k=0;k<keys.length;k++){
        try{
          var parsed=JSON.parse(store.getItem(keys[k])||"null");
          var user=asUser(parsed);
          if(user)return user;
        }catch(e){}
      }
    }
    return null;
  }
  function looksLoggedInPage(){
    var path=(location.pathname||"").toLowerCase();
    if(/\/(login|sign-in|signin|sign-up|signup|register|reset|forgot|oauth|2fa|mfa|turnstile)(\/|$)/.test(path))return false;
    if(/\/(console|panel|dashboard|app|admin|tokens?|channel|logs?|topup|wallet|personal|settings?|playground)(\/|$)/.test(path))return true;
    var password=document.querySelector("input[type=password]");
    if(password)return false;
    var text=((document.body&&document.body.innerText)||"").slice(0,8000);
    if(/退出登录|sign out|\blogout\b/i.test(text))return true;
    if((path==="/"||path==="")&&/当前额度|可用额度|令牌管理|渠道管理/.test(text))return true;
    return false;
  }
  function userFrom(payload){
    if(!payload||typeof payload!=="object")return null;
    if(payload.success===false)return null;
    return asUser(payload.data)||asUser(payload);
  }
  function snapshot(user, token, loggedIn){
    var prev=window.__yuconCapture||{};
    var found=user||readUser();
    var id=(found&&found.id!=null?String(found.id):"")||"";
    if(id==="0")id="";
    var access=looksAccessToken(token)||pickToken(found)||"";
    if(!access)access=looksAccessToken(prev.accessToken)||"";
    if(!id)id=prev.userId||"";
    if(id==="0")id="";
    var page=looksLoggedInPage();
    var ready=!!(access||id);
    return {
      ready:ready,
      loggedIn:ready,
      pageLoggedIn:page||ready,
      accessToken:access||"",
      refreshToken:"",
      cookies:document.cookie||prev.cookies||"",
      userId:id,
      username:nameOf(found)||prev.username||""
    };
  }
  window.__yuconScan=function(){return snapshot(readUser(), "", false);};
  function report(user, token, loggedIn){
    var session=snapshot(user, token, loggedIn);
    if(!session.loggedIn&&!session.userId&&!session.accessToken&&!session.pageLoggedIn)return;
    var prev=window.__yuconCapture||{};
    var same=prev.accessToken===session.accessToken&&prev.userId===session.userId&&prev.loggedIn===session.loggedIn&&prev.pageLoggedIn===session.pageLoggedIn;
    window.__yuconCapture=session;
    if(same)return;
    try{YuconHost.postMessage(JSON.stringify(session));}catch(e){}
  }
  function isSelfUrl(url){return String(url).indexOf("/api/user/self")>=0;}
  function isLoginUrl(url){return String(url).indexOf("/api/user/login")>=0||String(url).indexOf("/api/oauth")>=0;}
  function isTokenUrl(url){return String(url).indexOf("/api/user/token")>=0;}
  function isRefreshUrl(url){return String(url).indexOf("/api/user/auth/refresh")>=0;}
  function isAuthApi(url){return isLoginUrl(url)||isSelfUrl(url)||isTokenUrl(url)||isRefreshUrl(url);}
  function tokenFromAuth(value){
    var text=String(value||"").trim();
    var match=text.match(/^Bearer\s+(.+)$/i);
    return match?String(match[1]||"").trim():"";
  }
  function headerValue(headers, name){
    if(!headers)return "";
    var wanted=String(name||"").toLowerCase();
    try{
      if(typeof headers.get==="function"){
        var direct=headers.get(name)||headers.get(wanted)||headers.get(name.toUpperCase());
        if(direct)return String(direct);
      }
    }catch(e){}
    if(Array.isArray(headers)){
      for(var i=0;i<headers.length;i++){
        if(String(headers[i]&&headers[i][0]||"").toLowerCase()===wanted)return String(headers[i][1]||"");
      }
    }
    if(typeof headers==="object"){
      for(var key in headers){
        if(String(key).toLowerCase()===wanted)return String(headers[key]||"");
      }
    }
    return "";
  }
  function stealBearer(input, init){
    var token=tokenFromAuth(headerValue(init&&init.headers, "Authorization"));
    if(token)return token;
    try{
      if(input&&typeof input==="object")token=tokenFromAuth(headerValue(input.headers, "Authorization"));
    }catch(e){}
    return token||"";
  }
  function bundleFrom(payload){
    if(!payload||typeof payload!=="object")return null;
    var data=payload.data;
    if(data&&typeof data==="object"&&data.access_token)return data;
    if(payload.access_token)return payload;
    if(data&&data.data&&typeof data.data==="object"&&data.data.access_token)return data.data;
    return null;
  }
  function handlePayload(url, text){
    if(!text)return;
    var payload=null;
    try{payload=JSON.parse(text);}catch(e){return;}
    if(!payload||payload.success===false)return;
    var bundle=bundleFrom(payload);
    if(bundle&&bundle.access_token){
      report(bundle.user||userFrom(payload), String(bundle.access_token), true);
      return;
    }
    if(isLoginUrl(url)||isSelfUrl(url)){
      var user=userFrom(payload)||readUser();
      var issued=pickToken(payload.data)||pickToken(payload)||pickToken(user);
      if(user||issued)report(user, issued, true);
      return;
    }
    if(isTokenUrl(url)){
      var issued=pickToken(payload.data);
      if(issued)report(readUser()||userFrom(payload), issued, true);
    }
  }
  function requestUrl(input){
    if(!input)return "";
    if(typeof input==="string")return input;
    if(input.url)return String(input.url);
    return String(input);
  }
  async function fetchRefreshLocked(){
    if(window.__yuconCapture&&window.__yuconCapture.accessToken)return;
    var run=async function(){
      if(window.__yuconCapture&&window.__yuconCapture.accessToken)return;
      var res=await origFetch(location.origin+"/api/user/auth/refresh",{
        method:"POST",
        credentials:"include",
        headers:{Accept:"application/json","Cache-Control":"no-store"}
      });
      var text=await res.text();
      handlePayload("/api/user/auth/refresh", text);
    };
    try{
      if(navigator.locks&&navigator.locks.request){
        await navigator.locks.request("new-api:auth-refresh",{mode:"exclusive"},run);
      }else{
        await run();
      }
    }catch(e){}
  }
  async function tick(){
    if(window.__yuconCapture&&window.__yuconCapture.accessToken)return;
    if(looksLoggedInPage())report(readUser(), "", false);
    var force=!!window.__yuconRefreshAgain;
    var n=window.__yuconRefreshCount||0;
    if(force||(looksLoggedInPage()&&n<1)){
      window.__yuconRefreshAgain=false;
      window.__yuconRefreshCount=n+1;
      if(force){
        await fetchRefreshLocked();
      }else{
        setTimeout(function(){fetchRefreshLocked();}, 450);
      }
    }
  }
  var origFetch=window.__yuconOrigFetch||window.fetch;
  window.__yuconOrigFetch=origFetch;
  if(!window.__yuconWatch){
    window.__yuconWatch=true;
    window.fetch=function(input, init){
      var stolen="";
      try{
        stolen=stealBearer(input, init);
        if(stolen)report(readUser(), stolen, true);
      }catch(e){}
      var url=requestUrl(input);
      return origFetch.apply(this, arguments).then(function(res){
        try{
          if(stolen||isAuthApi(url)||String(url).indexOf("/api/user/")>=0){
            res.clone().text().then(function(text){handlePayload(url, text);}).catch(function(){});
          }
        }catch(e){}
        return res;
      });
    };
    if(window.XMLHttpRequest&&XMLHttpRequest.prototype){
      var xhrOpen=XMLHttpRequest.prototype.open;
      var xhrSet=XMLHttpRequest.prototype.setRequestHeader;
      var xhrSend=XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open=function(method, url){
        this.__yuconUrl=String(url||"");
        return xhrOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.setRequestHeader=function(name, value){
        try{
          if(String(name||"").toLowerCase()==="authorization"){
            var stolen=tokenFromAuth(value);
            if(stolen)report(readUser(), stolen, true);
          }
        }catch(e){}
        return xhrSet.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send=function(){
        var xhr=this;
        xhr.addEventListener("load", function(){
          try{handlePayload(xhr.__yuconUrl||"", xhr.responseText);}catch(e){}
        });
        return xhrSend.apply(this, arguments);
      };
    }
    setInterval(tick, 800);
    tick();
  }else{
    tick();
  }
})();
''';
  }

  String _assistScript() {
    return '(function(){'
        'var cred={user:${jsonEncode(widget.email)},password:${jsonEncode(widget.password)}};'
        'function setValue(el,value){'
        'if(!el||!value)return;'
        'var proto=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,"value");'
        'if(proto&&proto.set){proto.set.call(el,value)}else{el.value=value}'
        'el.dispatchEvent(new Event("input",{bubbles:true}));'
        'el.dispatchEvent(new Event("change",{bubbles:true}));'
        '}'
        'var userInput=document.querySelector("input[name=username],input[name=email],input[type=email],input[autocomplete=username],input[autocomplete=email]");'
        'var passwordInput=document.querySelector("input[type=password]");'
        'setValue(userInput,cred.user);'
        'setValue(passwordInput,cred.password);'
        'var turnstile=document.querySelector("textarea[name=cf-turnstile-response],input[name=cf-turnstile-response]");'
        'if(turnstile&&turnstile.value&&cred.user&&cred.password){'
        'var button=document.querySelector("form button[type=submit],form button");'
        'if(button&&!button.disabled&&!button.dataset.ycClicked){button.dataset.ycClicked="1";button.click();}'
        '}'
        '})();';
  }

  @override
  Widget build(BuildContext context) {
    return SecureScope(
      child: PopScope(
      canPop: !_networkBlocked,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _finished) {
          return;
        }
        _leaveBlocked();
      },
      child: Scaffold(
        appBar: YuconAppBar(
          title: '站点登录',
          subtitle: _networkBlocked
              ? '这个网站不支持当前网络访问'
              : (_looksLoggedIn ? '已检测到登录，正在自动返回' : '已登录会自动返回，未登录则在页面里完成登录'),
          actions: [
            if (_looksLoggedIn && !_networkBlocked)
              HeaderTextAction(label: '使用当前登录', onPressed: () => unawaited(_useCurrentLogin())),
          ],
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_networkBlocked)
              ColoredBox(
                color: ThemeDefine.kColorPage,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(15, 16, 15, 24),
                  children: [
                    YuconCard(
                      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$_siteHost 不支持当前网络访问',
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.3),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '页面里的 Sorry, you have been blocked 表示这个网站不允许你现在所用的网络打开它，不是账号填错，也不是登录失败。请到「我的」换一个可用代理后再连。',
                            style: TextStyle(color: ThemeDefine.kColorText, fontSize: 13, height: 1.5),
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(label: '返回去配置代理', onPressed: _leaveBlocked),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }
}

Future<SiteSession> captureSiteSession(
  BuildContext context, {
  required String baseUrl,
  PlatformType platformType = PlatformType.newapi,
  String email = '',
  String password = '',
  NetworkProxy? proxy,
}) async {
  await applyWebViewProxy(proxy);
  try {
    if (!context.mounted) {
      throw ApiError('已取消登录');
    }
    final base = normalizeBaseUrl(baseUrl);
    final loginUrl = '$base/sign-in';
    final startUrl = platformType == PlatformType.sub2api ? loginUrl : '$base/';
    final result = await Navigator.of(context).push<Object>(
      MaterialPageRoute(
        builder: (_) => SiteLoginScreen(
          loginUrl: loginUrl,
          startUrl: startUrl,
          kind: platformType,
          email: email,
          password: password,
        ),
      ),
    );
    if (result is SiteNetworkBlocked) {
      throw ApiError(kSiteNetworkBlockedMessage);
    }
    if (result is! SiteSession || !result.hasAuth) {
      throw ApiError('已取消登录');
    }
    return result;
  } finally {
    await applyWebViewProxy(null);
  }
}
