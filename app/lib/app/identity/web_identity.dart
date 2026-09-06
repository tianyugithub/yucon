import 'dart:convert';

const googleIdentityProvider = 'google';

const githubIdentityProvider = 'github';

const googleIdentityHomeUrl = 'https://myaccount.google.com/';

const githubIdentityHomeUrl = 'https://github.com/settings/profile';

bool isOAuthIdentityProvider(String provider) {
  return provider == googleIdentityProvider ||
      provider == githubIdentityProvider;
}

String legacyIdentitySessionId(String provider) => 'legacy-$provider';

String identityHomeUrl(String provider) {
  if (provider == githubIdentityProvider) {
    return githubIdentityHomeUrl;
  }
  return googleIdentityHomeUrl;
}

String bareHost(String host) {
  var value = host.trim().toLowerCase();
  if (value.startsWith('.')) {
    value = value.substring(1);
  }
  return value;
}

bool looksLikeSameSiteHost(String candidate, String siteHost) {
  final a = bareHost(candidate);
  final b = bareHost(siteHost);
  if (a.isEmpty || b.isEmpty) {
    return false;
  }
  if (a == b) {
    return true;
  }
  if (a.endsWith('.$b') && b.contains('.')) {
    return true;
  }
  return b.endsWith('.$a') && a.contains('.');
}

String? siteOriginOf(String raw) {
  var trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
    trimmed = 'https://$trimmed';
  }
  while (trimmed.endsWith('/')) {
    trimmed = trimmed.substring(0, trimmed.length - 1);
  }
  final uri = Uri.tryParse(trimmed);
  if (uri == null || uri.host.trim().isEmpty) {
    return null;
  }
  final origin = uri.hasPort
      ? '${uri.scheme}://${uri.host}:${uri.port}'
      : '${uri.scheme}://${uri.host}';
  return origin;
}

List<String> siteWebDataOrigins(
  String baseUrl, {
  Iterable<String> extraUrls = const [],
}) {
  final base = siteOriginOf(baseUrl);
  if (base == null) {
    return const [];
  }
  final siteHost = Uri.parse(base).host;
  final origins = <String>{base};
  for (final raw in extraUrls) {
    final origin = siteOriginOf(raw);
    if (origin == null) {
      continue;
    }
    if (looksLikeSameSiteHost(Uri.parse(origin).host, siteHost)) {
      origins.add(origin);
    }
  }
  return origins.toList();
}

List<String> siteOAuthStartUrls(
  String baseUrl,
  String provider, {
  bool sub2 = false,
}) {
  var base = baseUrl.trim();
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  final kind = provider == githubIdentityProvider ? 'github' : 'google';
  if (sub2) {
    return [
      '$base/api/v1/auth/oauth/$kind/start?redirect=/dashboard',
      '$base/api/v1/auth/oauth/$kind/start',
    ];
  }
  if (provider == githubIdentityProvider) {
    return ['$base/oauth/github', '$base/api/oauth/github'];
  }
  return [
    '$base/oauth/google',
    '$base/api/oauth/google',
    '$base/oauth/oidc',
    '$base/api/oauth/oidc',
  ];
}

bool looksLikeIdentityHost(String url, String provider) {
  final host = (Uri.tryParse(url)?.host ?? url).toLowerCase();
  if (provider == githubIdentityProvider) {
    return host == 'github.com' || host.endsWith('.github.com');
  }
  return host.contains('google.') ||
      host.contains('youtube.com') ||
      host.contains('gstatic.com');
}

String siteOAuthClickScript(String provider) {
  final kind = provider == githubIdentityProvider ? 'github' : 'google';
  final needles = provider == githubIdentityProvider
      ? const [
          '使用github登录',
          '使用github登陆',
          '使用github账号登录',
          '使用github帐户登录',
          'continuewithgithub',
          'signinwithgithub',
          'loginwithgithub',
        ]
      : const [
          '使用google登录',
          '使用google登陆',
          '使用google账号登录',
          '使用google帐户登录',
          '使用谷歌登录',
          '使用谷歌账号登录',
          'continuewithgoogle',
          'signinwithgoogle',
          'loginwithgoogle',
        ];
  return '''
(function(){
  var kind=${jsonEncode(kind)};
  var needles=${jsonEncode(needles)};
  try {
    var host=(location.hostname||"").toLowerCase();
    if(kind==="google" && (host.indexOf("google.")>=0 || host.indexOf("youtube.com")>=0 || host.indexOf("gstatic.com")>=0)) return "0";
    if(kind==="github" && (host==="github.com" || host.endsWith(".github.com"))) return "0";
  } catch (e) {}
  function visible(el){
    if(!el) return false;
    try {
      var s=window.getComputedStyle(el);
      if(s.display==="none" || s.visibility==="hidden" || s.opacity==="0") return false;
      var r=el.getBoundingClientRect();
      return r.width>0 && r.height>0;
    } catch (e) { return false; }
  }
  function clickable(el){
    if(!el || !el.tagName) return false;
    var tag=el.tagName.toLowerCase();
    if(tag==="button" || tag==="a") return true;
    if(tag==="input"){
      var type=String(el.type||"").toLowerCase();
      return type==="button" || type==="submit" || type==="image";
    }
    var role=String(el.getAttribute("role")||"").toLowerCase();
    if(role==="button" || role==="link") return true;
    var cls=String(el.className||"").toLowerCase();
    return cls.indexOf("btn")>=0 || cls.indexOf("button")>=0 || cls.indexOf("oauth")>=0;
  }
  function blocked(el){
    if(!el) return true;
    if(el.disabled) return true;
    if(String(el.getAttribute("aria-disabled")||"")==="true") return true;
    if(el.getAttribute("disabled")!=null) return true;
    return false;
  }
  function acceptAgreement(doc){
    var boxes=doc.querySelectorAll("input[type=checkbox]");
    for (var i=0;i<boxes.length;i++){
      var el=boxes[i];
      if(!visible(el) || el.checked) continue;
      var wrap=el.closest("label")||el.parentElement||el;
      var around=String((wrap&&(wrap.innerText||wrap.textContent))||el.getAttribute("aria-label")||"");
      if(/协议|同意|terms|agreement|privacy|我已阅读|已阅读/.test(around)){
        try { el.click(); } catch (e) {}
      }
    }
  }
  function compact(s){
    return String(s||"").toLowerCase().replace(/[ \\t\\n\\r]+/g,"").replace(/[()\\[\\]·•_-]/g,"");
  }
  function hayOf(el){
    var href="";
    try { href=String(el.getAttribute("href")||el.href||"").toLowerCase(); } catch (e) {}
    var text=String(el.innerText||el.textContent||el.getAttribute("aria-label")||el.getAttribute("title")||"").toLowerCase();
    var cls="";
    try { cls=String(el.getAttribute("class")||el.className||"").toLowerCase(); } catch (e) {}
    var html="";
    try { html=String(el.innerHTML||"").toLowerCase(); } catch (e) {}
    return {href:href, text:text, cls:cls, html:html, compact:compact(text), hay:(href+" "+text+" "+cls+" "+html)};
  }
  function offsite(href){
    if(!href) return false;
    if(kind==="github"){
      return href.indexOf("github.com")>=0 && href.indexOf("/login/oauth")<0 && href.indexOf("/oauth/")<0 && href.indexOf("api/oauth")<0;
    }
    return href.indexOf("accounts.google")<0 && (href.indexOf("google.")>=0 || href.indexOf("youtube.com")>=0) && href.indexOf("/oauth")<0 && href.indexOf("/o/oauth")<0;
  }
  function loginish(text){
    return /登录|登陆|login|signin|sign-in|continue|授权|账号|帐户|快捷|使用/.test(String(text||"").toLowerCase());
  }
  function hasKind(info){
    if(kind==="github") return info.hay.indexOf("github")>=0;
    return info.hay.indexOf("google")>=0 || info.hay.indexOf("谷歌")>=0 || info.hay.indexOf("oidc")>=0;
  }
  function score(el){
    var info=hayOf(el);
    if(offsite(info.href)) return 0;
    if(kind==="google" && info.hay.indexOf("github")>=0 && info.hay.indexOf("google")<0 && info.hay.indexOf("谷歌")<0 && info.hay.indexOf("oidc")<0) return 0;
    if(kind==="github" && (info.hay.indexOf("google")>=0 || info.hay.indexOf("谷歌")>=0) && info.hay.indexOf("github")<0) return 0;
    var href=info.href;
    if(kind==="github"){
      if(href.indexOf("/auth/oauth/github")>=0 || href.indexOf("/oauth/github")>=0 || href.indexOf("api/oauth/github")>=0) return 9;
    } else if(href.indexOf("/auth/oauth/google")>=0 || href.indexOf("/oauth/google")>=0 || href.indexOf("/oauth/oidc")>=0 || href.indexOf("api/oauth/google")>=0 || href.indexOf("api/oauth/oidc")>=0){
      return 9;
    }
    for (var n=0;n<needles.length;n++){
      if(info.compact.indexOf(needles[n])>=0) return 8;
    }
    if(hasKind(info) && loginish(info.text)) return 7;
    if(clickable(el) && hasKind(info) && (el.tagName==="BUTTON" || el.tagName==="A" || el.getAttribute("role")==="button")){
      var short=info.compact;
      if(kind==="github" && (short==="github" || short==="github登录")) return 6;
      if(kind==="google" && (short==="google" || short==="谷歌" || short==="google登录" || short==="谷歌登录")) return 6;
      return 5;
    }
    if(clickable(el) && (info.html.indexOf(kind)>=0 || info.cls.indexOf(kind)>=0)) return 4;
    return 0;
  }
  function fire(el){
    if(!el) return false;
    var target=el;
    try {
      var hostEl=el.closest("button,a,[role=button],.btn,[class*='oauth']");
      if(hostEl) target=hostEl;
    } catch (e) {}
    try { target.removeAttribute("target"); } catch (e) {}
    try { target.setAttribute("target","_self"); } catch (e) {}
    try {
      ["pointerdown","mousedown","pointerup","mouseup","click"].forEach(function(type){
        target.dispatchEvent(new MouseEvent(type,{bubbles:true,cancelable:true,composed:true,view:window,buttons:1}));
      });
      if(typeof target.click==="function") target.click();
      return true;
    } catch (e) {
      try { target.click(); return true; } catch (err) { return false; }
    }
  }
  function collect(root, acc){
    if(!root || !root.querySelectorAll) return;
    var nodes=root.querySelectorAll("a,button,input[type=button],input[type=submit],[role=button],[role=link],.btn,[class*='btn'],[class*='button'],[class*='oauth'],[class*='github'],[class*='google']");
    for (var i=0;i<nodes.length;i++) acc.push(nodes[i]);
    var labeled=root.querySelectorAll("a,button,div,span,p,li,label,h1,h2,h3,h4");
    for (var k=0;k<labeled.length;k++){
      var t=compact(labeled[k].innerText||labeled[k].textContent||"");
      if(t.length<4 || t.length>40) continue;
      var hit=false;
      for (var n=0;n<needles.length;n++){
        if(t.indexOf(needles[n])>=0){ hit=true; break; }
      }
      if(!hit && kind==="github" && t.indexOf("github")>=0 && (t.indexOf("登录")>=0 || t.indexOf("登陆")>=0 || t.indexOf("login")>=0 || t.indexOf("signin")>=0)) hit=true;
      if(!hit && kind==="google" && (t.indexOf("google")>=0 || t.indexOf("谷歌")>=0) && (t.indexOf("登录")>=0 || t.indexOf("登陆")>=0 || t.indexOf("login")>=0 || t.indexOf("signin")>=0)) hit=true;
      if(hit) acc.push(labeled[k]);
    }
    var all=root.querySelectorAll("*");
    for (var j=0;j<all.length;j++){
      if(all[j].shadowRoot) collect(all[j].shadowRoot, acc);
    }
  }
  function docs(){
    var list=[document];
    try {
      var frames=document.querySelectorAll("iframe");
      for (var i=0;i<frames.length;i++){
        try {
          var d=frames[i].contentDocument||(frames[i].contentWindow&&frames[i].contentWindow.document);
          if(d) list.push(d);
        } catch (e) {}
      }
    } catch (e) {}
    return list;
  }
  var seen=null, seenScore=0, pending=false;
  var pages=docs();
  for (var p=0;p<pages.length;p++){
    try { acceptAgreement(pages[p]); } catch (e) {}
    var nodes=[];
    collect(pages[p], nodes);
    for (var i=0;i<nodes.length;i++){
      var el=nodes[i];
      if(!visible(el)) continue;
      var s=score(el);
      if(s<4) continue;
      if(blocked(el)){ pending=true; continue; }
      if(s>seenScore){ seenScore=s; seen=el; }
    }
  }
  if(seen) return fire(seen) ? "1" : "0";
  if(pending) return "wait";
  return "0";
})();
''';
}

String siteOAuthNavigateScript(String url) {
  return '(function(){try{location.assign(${jsonEncode(url)});}catch(e){try{location.href=${jsonEncode(url)};}catch(err){}}return "1";})();';
}

const googleIdentityCookieUrls = [
  'https://accounts.google.com/',
  'https://myaccount.google.com/',
  'https://www.google.com/',
];

const githubIdentityCookieUrls = [
  'https://github.com/',
  'https://github.com/settings/profile',
  'https://gist.github.com/',
];

const googleChromeMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

class WebIdentityJar {
  const WebIdentityJar({required this.url, required this.header});

  final String url;
  final String header;

  Map<String, dynamic> toJson() => {'url': url, 'header': header};

  factory WebIdentityJar.fromJson(Map<String, dynamic> json) => WebIdentityJar(
    url: (json['url'] ?? '').toString(),
    header: (json['header'] ?? json['cookies'] ?? '').toString(),
  );
}

class WebIdentityCookie {
  const WebIdentityCookie({
    required this.url,
    required this.name,
    required this.value,
    this.domain = '',
    this.path = '/',
    this.secure = true,
    this.maxAge,
  });

  final String url;
  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final int? maxAge;

  Map<String, dynamic> toNative() => {
    'url': url,
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    if (maxAge != null) 'maxAge': maxAge,
  };
}

class WebIdentitySnapshot {
  const WebIdentitySnapshot({
    required this.provider,
    this.accountId = '',
    this.email = '',
    this.updatedAt = '',
    this.jars = const [],
  });

  final String provider;
  final String accountId;
  final String email;
  final String updatedAt;
  final List<WebIdentityJar> jars;

  bool get hasGoogleSession {
    return jars.any((jar) {
      return parseCookieHeader(jar.header).any((pair) {
        final name = pair.$1.toLowerCase();
        return name == 'sid' ||
            name.contains('psid') ||
            name.endsWith('apisid');
      });
    });
  }

  bool get hasGitHubSession {
    return jars.any((jar) {
      return parseCookieHeader(jar.header)
          .any((pair) => pair.$1.toLowerCase() == 'user_session');
    });
  }

  bool get isConnected {
    if (provider == githubIdentityProvider) {
      return hasGitHubSession;
    }
    return hasGoogleSession;
  }

  String get label {
    final mail = email.trim();
    if (mail.isNotEmpty) {
      return mail;
    }
    return isConnected ? '已记住登录' : '未连接';
  }

  WebIdentitySnapshot copyWith({
    String? provider,
    String? accountId,
    String? email,
    String? updatedAt,
    List<WebIdentityJar>? jars,
  }) {
    return WebIdentitySnapshot(
      provider: provider ?? this.provider,
      accountId: accountId ?? this.accountId,
      email: email ?? this.email,
      updatedAt: updatedAt ?? this.updatedAt,
      jars: jars ?? this.jars,
    );
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'accountId': accountId,
    'email': email,
    'updatedAt': updatedAt,
    'jars': jars.map((jar) => jar.toJson()).toList(),
  };

  factory WebIdentitySnapshot.fromJson(Map<String, dynamic> json) {
    final rawJars = json['jars'];
    return WebIdentitySnapshot(
      provider: (json['provider'] ?? googleIdentityProvider).toString(),
      accountId: (json['accountId'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
      jars: rawJars is List
          ? rawJars
                .whereType<Map>()
                .map(
                  (item) =>
                      WebIdentityJar.fromJson(Map<String, dynamic>.from(item)),
                )
                .where(
                  (jar) =>
                      jar.url.trim().isNotEmpty && jar.header.trim().isNotEmpty,
                )
                .toList()
          : const [],
    );
  }
}

bool looksLikeGoogleSignIn(String url) {
  final uri = Uri.tryParse(url);
  final host = (uri?.host ?? url).toLowerCase();
  final path = (uri?.path ?? url).toLowerCase();
  final full = url.toLowerCase();
  if (!host.contains('google.') && !host.contains('youtube.com')) {
    return false;
  }
  return path.contains('/signin') ||
      path.contains('/servicelogin') ||
      full.contains('servicelogin') ||
      path.contains('/identifier') ||
      path.contains('/challenge') ||
      path.contains('/lifecycle') ||
      path.contains('/addsession');
}

bool looksLikeGoogleLoggedIn(String url) {
  final uri = Uri.tryParse(url);
  final host = (uri?.host ?? '').toLowerCase();
  final path = (uri?.path ?? '').toLowerCase();
  if (host.contains('myaccount.google.')) {
    return !looksLikeGoogleSignIn(url);
  }
  if (host.contains('accounts.google.')) {
    return path.contains('/b/') ||
        path.contains('manageaccount') ||
        path.contains('/signin/continue');
  }
  return false;
}

bool looksLikeGoogleCaptcha(String url) {
  final full = url.toLowerCase();
  return full.contains('recaptcha') ||
      full.contains('/captcha') ||
      full.contains('challenge/ipp') ||
      full.contains('challenge/az') ||
      full.contains('deniedsigninrejected') ||
      full.contains('signin/rejected');
}

bool looksLikeGoogleCookieError(String url) {
  final full = url.toLowerCase();
  return full.contains('javascriptcookie') ||
      full.contains('cookiemismatch') ||
      full.contains('cookieerror') ||
      full.contains('cookiesdisabled') ||
      full.contains('error=nocookies');
}

String chromeLikeUserAgent(String? raw) {
  var ua = (raw ?? '').trim();
  if (ua.isEmpty) {
    return googleChromeMobileUserAgent;
  }
  ua = ua.replaceAll(RegExp(r';\s*wv'), '');
  ua = ua.replaceAll('Version/4.0 ', '');
  ua = ua.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  if (!ua.contains('Mozilla/5.0') || !ua.contains('AppleWebKit/')) {
    return googleChromeMobileUserAgent;
  }
  return ua;
}

List<(String, String)> parseCookieHeader(String header) {
  final pairs = <(String, String)>[];
  for (final part in header.split(';')) {
    final trimmed = part.trim();
    final eq = trimmed.indexOf('=');
    if (eq <= 0) {
      continue;
    }
    final name = trimmed.substring(0, eq).trim();
    final value = trimmed.substring(eq + 1);
    if (name.isEmpty) {
      continue;
    }
    pairs.add((name, value));
  }
  return pairs;
}

bool isHostOnlyCookie(String name) {
  return name.startsWith('__Host-') || name.startsWith('__host-');
}

bool isGoogleHostCookie(String name) => isHostOnlyCookie(name);

bool isGoogleAuthCookie(String name) {
  final lower = name.toLowerCase();
  if (lower == 'sid' ||
      lower == 'hsid' ||
      lower == 'ssid' ||
      lower == 'lsid' ||
      lower == 'sidcc' ||
      lower == 'account_chooser' ||
      lower == 'gaps') {
    return true;
  }
  if (lower.contains('gap') && isGoogleHostCookie(name)) {
    return true;
  }
  return lower.endsWith('apisid') ||
      lower.contains('psid') ||
      lower.endsWith('psidcc');
}

bool isGoogleWideCookie(String name) {
  return isGoogleAuthCookie(name) && !isGoogleHostCookie(name);
}

String googleAuthCookieHeader(String header) {
  return parseCookieHeader(header)
      .where((pair) => isGoogleAuthCookie(pair.$1) && pair.$2.trim().isNotEmpty)
      .map((pair) => '${pair.$1}=${pair.$2}')
      .join('; ');
}

String googleCookieDomainFor(String name, String url) {
  if (isGoogleHostCookie(name)) {
    return '';
  }
  if (isGoogleWideCookie(name)) {
    return '.google.com';
  }
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) {
    return '.google.com';
  }
  return host.startsWith('.') ? host : host;
}

String googleCookieUrlFor(String name, String jarUrl) {
  if (isGoogleHostCookie(name)) {
    return jarUrl;
  }
  if (googleCookieDomainFor(name, jarUrl) == '.google.com') {
    return 'https://accounts.google.com/';
  }
  return jarUrl;
}

List<WebIdentityCookie> cookiesFromSnapshot(
  WebIdentitySnapshot snapshot, {
  int? maxAge,
}) {
  final cookies = <WebIdentityCookie>[];
  final seen = <String>{};
  for (final jar in snapshot.jars) {
    for (final pair in parseCookieHeader(jar.header)) {
      if (!isAuthCookieFor(snapshot.provider, pair.$1) ||
          pair.$2.trim().isEmpty) {
        continue;
      }
      final domain = cookieDomainFor(snapshot.provider, pair.$1, jar.url);
      for (final url in restoreUrlsFor(
        snapshot.provider,
        pair.$1,
        jar.url,
      )) {
        final key = '$url|${domain.isEmpty ? url : domain}|${pair.$1}';
        if (!seen.add(key)) {
          continue;
        }
        cookies.add(
          WebIdentityCookie(
            url: url,
            name: pair.$1,
            value: pair.$2,
            domain: domain,
            path: '/',
            secure: true,
            maxAge: maxAge,
          ),
        );
      }
    }
  }
  return cookies;
}

List<String> restoreUrlsFor(
  String provider,
  String name,
  String jarUrl,
) {
  return [cookieUrlFor(provider, name, jarUrl)];
}

bool isAuthCookieFor(String provider, String name) {
  if (provider == githubIdentityProvider) {
    return isGitHubAuthCookie(name);
  }
  return isGoogleAuthCookie(name);
}

String cookieDomainFor(String provider, String name, String url) {
  if (provider == githubIdentityProvider) {
    return githubCookieDomainFor(name, url);
  }
  return googleCookieDomainFor(name, url);
}

String cookieUrlFor(String provider, String name, String jarUrl) {
  if (provider == githubIdentityProvider) {
    return githubCookieUrlFor(name, jarUrl);
  }
  return googleCookieUrlFor(name, jarUrl);
}

String? parseGoogleEmailFromJs(Object? raw) {
  var text = raw?.toString().trim() ?? '';
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1);
  }
  text = text.replaceAll(r'\"', '"').trim();
  if (text.isEmpty || text == 'null' || text == 'undefined') {
    return null;
  }
  final match = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  ).firstMatch(text);
  final email = (match?.group(0) ?? text).trim();
  if (!email.contains('@')) {
    return null;
  }
  return email;
}

bool looksLikeGitHubHost(String url) {
  final host = (Uri.tryParse(url)?.host ?? url).toLowerCase();
  return host == 'github.com' || host.endsWith('.github.com');
}

bool looksLikeGitHubSignIn(String url) {
  if (!looksLikeGitHubHost(url)) {
    return false;
  }
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path == '/login' ||
      path.startsWith('/login/') ||
      path == '/session' ||
      path.startsWith('/session/') ||
      path.contains('/sessions/two-factor') ||
      path.contains('/sessions/verified-device') ||
      path.contains('/password_reset') ||
      path.contains('/saml/');
}

bool looksLikeGitHubLoggedIn(String url) {
  if (!looksLikeGitHubHost(url) ||
      looksLikeGitHubSignIn(url) ||
      looksLikeGitHubCaptcha(url)) {
    return false;
  }
  final path = (Uri.tryParse(url)?.path ?? url).toLowerCase();
  return path.contains('/settings') ||
      path.contains('/notifications') ||
      path.contains('/dashboard') ||
      path.contains('/account');
}

bool looksLikeGitHubCaptcha(String url) {
  final full = url.toLowerCase();
  return full.contains('octocaptcha') ||
      full.contains('arkose') ||
      full.contains('captcha');
}

bool isGitHubAuthCookie(String name) {
  final lower = name.toLowerCase();
  return lower == 'user_session' ||
      lower == '_gh_sess' ||
      lower == 'logged_in' ||
      lower == 'dotcom_user' ||
      lower == '_device_id' ||
      lower.contains('user_session');
}

bool isGitHubWideCookie(String name) {
  return isGitHubAuthCookie(name) && !isHostOnlyCookie(name);
}

String githubAuthCookieHeader(String header) {
  return parseCookieHeader(header)
      .where((pair) => isGitHubAuthCookie(pair.$1) && pair.$2.trim().isNotEmpty)
      .map((pair) => '${pair.$1}=${pair.$2}')
      .join('; ');
}

String githubCookieDomainFor(String name, String url) {
  if (isHostOnlyCookie(name)) {
    return '';
  }
  if (isGitHubWideCookie(name)) {
    return '.github.com';
  }
  final host = Uri.tryParse(url)?.host ?? '';
  if (host.isEmpty) {
    return '.github.com';
  }
  return host.startsWith('.') ? host : host;
}

String githubCookieUrlFor(String name, String jarUrl) {
  if (isHostOnlyCookie(name)) {
    return jarUrl.startsWith('https://gist.') ? jarUrl : 'https://github.com/';
  }
  if (githubCookieDomainFor(name, jarUrl) == '.github.com') {
    return 'https://github.com/';
  }
  return jarUrl;
}

String? parseGitHubLoginFromJs(Object? raw) {
  var text = raw?.toString().trim() ?? '';
  if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
    text = text.substring(1, text.length - 1);
  }
  text = text.replaceAll(r'\"', '"').trim();
  if (text.isEmpty ||
      text == 'null' ||
      text == 'undefined' ||
      text == 'false') {
    return null;
  }
  final email = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  ).firstMatch(text);
  if (email != null) {
    return email.group(0);
  }
  final login = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9]|-(?=[A-Za-z0-9])){0,38}$')
      .firstMatch(text);
  return login?.group(0);
}

enum IdentitySessionFreshness { missing, alive, expired, unknown }

bool identitySessionNeedsLogin(IdentitySessionFreshness value) {
  return value != IdentitySessionFreshness.alive;
}

String identityCookieHeader(WebIdentitySnapshot snapshot) {
  final parts = <String>[];
  final seen = <String>{};
  for (final jar in snapshot.jars) {
    for (final pair in parseCookieHeader(jar.header)) {
      final key = pair.$1.toLowerCase();
      if (key.isEmpty || !seen.add(key)) {
        continue;
      }
      parts.add('${pair.$1}=${pair.$2}');
    }
  }
  return parts.join('; ');
}

IdentitySessionFreshness classifyIdentityProbeResult({
  required String provider,
  required String url,
  int status = 200,
}) {
  if (status == 401 || status == 403) {
    return IdentitySessionFreshness.expired;
  }
  if (provider == githubIdentityProvider) {
    if (looksLikeGitHubSignIn(url) || looksLikeGitHubCaptcha(url)) {
      return IdentitySessionFreshness.expired;
    }
    if (looksLikeGitHubLoggedIn(url)) {
      return IdentitySessionFreshness.alive;
    }
    if (status >= 200 &&
        status < 400 &&
        looksLikeGitHubHost(url) &&
        !looksLikeGitHubSignIn(url)) {
      return IdentitySessionFreshness.alive;
    }
    return IdentitySessionFreshness.unknown;
  }
  if (looksLikeGoogleCookieError(url)) {
    return IdentitySessionFreshness.expired;
  }
  if (looksLikeGoogleCaptcha(url)) {
    return IdentitySessionFreshness.unknown;
  }
  if (looksLikeGoogleSignIn(url) && !looksLikeGoogleLoggedIn(url)) {
    return IdentitySessionFreshness.expired;
  }
  if (looksLikeGoogleLoggedIn(url)) {
    return IdentitySessionFreshness.alive;
  }
  return IdentitySessionFreshness.unknown;
}

class IdentityLoginAccount {
  const IdentityLoginAccount({
    this.id = '',
    required this.provider,
    this.username = '',
    this.password = '',
  });

  final String id;
  final String provider;
  final String username;
  final String password;

  bool get isEmpty => username.trim().isEmpty && password.isEmpty;

  bool get canFill => username.trim().isNotEmpty || password.isNotEmpty;

  String get label {
    final name = username.trim();
    return name.isEmpty ? '未命名账号' : name;
  }

  IdentityLoginAccount copyWith({
    String? id,
    String? provider,
    String? username,
    String? password,
  }) {
    return IdentityLoginAccount(
      id: id ?? this.id,
      provider: provider ?? this.provider,
      username: username ?? this.username,
      password: password ?? this.password,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'provider': provider,
    'username': username,
    'password': password,
  };

  factory IdentityLoginAccount.fromJson(Map<String, dynamic> json) {
    return IdentityLoginAccount(
      id: (json['id'] ?? '').toString(),
      provider: (json['provider'] ?? '').toString(),
      username: (json['username'] ?? json['email'] ?? '').toString(),
      password: (json['password'] ?? '').toString(),
    );
  }
}

class IdentityLoginBundle {
  const IdentityLoginBundle({
    this.accounts = const [],
    this.selectedIds = const {},
  });

  final List<IdentityLoginAccount> accounts;
  final Map<String, String> selectedIds;

  Map<String, dynamic> toJson() => {
    'accounts': [for (final account in accounts) account.toJson()],
    'selected': selectedIds,
  };

  factory IdentityLoginBundle.fromJson(Object? raw) {
    if (raw is! Map) {
      return const IdentityLoginBundle();
    }
    final map = Map<String, dynamic>.from(raw);
    final rawAccounts = map['accounts'];
    if (rawAccounts is List) {
      final accounts = <IdentityLoginAccount>[];
      for (final item in rawAccounts) {
        if (item is! Map) {
          continue;
        }
        var account = IdentityLoginAccount.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (account.provider.isEmpty ||
            account.isEmpty ||
            !isOAuthIdentityProvider(account.provider)) {
          continue;
        }
        if (account.id.isEmpty) {
          account = account.copyWith(
            id: 'login-${account.provider}-${accounts.length}',
          );
        }
        accounts.add(account);
      }
      final selected = <String, String>{};
      final rawSelected = map['selected'];
      if (rawSelected is Map) {
        for (final entry in rawSelected.entries) {
          final provider = entry.key.toString();
          final id = entry.value.toString();
          if (!isOAuthIdentityProvider(provider) || id.isEmpty) {
            continue;
          }
          selected[provider] = id;
        }
      }
      return IdentityLoginBundle(accounts: accounts, selectedIds: selected);
    }
    final accounts = <IdentityLoginAccount>[];
    final selected = <String, String>{};
    for (final entry in map.entries) {
      if (entry.value is! Map) {
        continue;
      }
      final provider = entry.key.toString();
      if (!isOAuthIdentityProvider(provider)) {
        continue;
      }
      final record = Map<String, dynamic>.from(entry.value as Map);
      var account = IdentityLoginAccount.fromJson({
        ...record,
        'provider': provider,
        'id': (record['id'] ?? 'login-$provider').toString(),
      });
      if (account.isEmpty) {
        continue;
      }
      if (account.id.isEmpty) {
        account = account.copyWith(id: 'login-$provider');
      }
      accounts.add(account);
      selected[provider] = account.id;
    }
    return IdentityLoginBundle(accounts: accounts, selectedIds: selected);
  }
}

String identityGroupTitle(String provider) {
  if (provider == githubIdentityProvider) {
    return 'GitHub';
  }
  return 'Google';
}

String identityProviderTitle(String provider) {
  if (provider == githubIdentityProvider) {
    return 'GitHub 登录';
  }
  return 'Google 登录';
}

String identityLoginTitle(String provider) {
  if (provider == githubIdentityProvider) {
    return 'GitHub 账号';
  }
  return 'Google 账号';
}

String identitySessionFailureHint(
  String provider,
  IdentitySessionFreshness fresh, {
  bool register = false,
}) {
  final name = identityLoginTitle(provider);
  switch (fresh) {
    case IdentitySessionFreshness.alive:
      return '';
    case IdentitySessionFreshness.expired:
      return '$name登录已过期，请先重新登录后再${register ? '注册' : '打开站点'}';
    case IdentitySessionFreshness.missing:
      return '还没有记住这个$name登录，请先在身份里登录';
    case IdentitySessionFreshness.unknown:
      return '无法确认$name登录是否有效，请重新登录后再试';
  }
}

String identityWindowTitle(String provider, {IdentityLoginAccount? login}) {
  final name = login?.label.trim() ?? '';
  if (name.isNotEmpty) {
    return name;
  }
  return identityProviderTitle(provider);
}

String identityLoginUsernameLabel(String provider) {
  if (provider == githubIdentityProvider) {
    return '用户名或邮箱';
  }
  return '邮箱';
}

bool shouldAutofillIdentityLogin(String provider, String url) {
  if (url.trim().isEmpty) {
    return false;
  }
  if (provider == githubIdentityProvider) {
    return looksLikeGitHubSignIn(url);
  }
  return looksLikeGoogleSignIn(url) && !looksLikeGoogleLoggedIn(url);
}

String identityAutofillScript(IdentityLoginAccount account) {
  final user = jsonEncode(account.username.trim());
  final pass = jsonEncode(account.password);
  return '''
(function(){
  var cred={user:$user,password:$pass};
  if(!cred.user && !cred.password) return "0";
  function visible(el){
    if(!el || el.disabled) return false;
    var style=window.getComputedStyle(el);
    if(style.visibility==="hidden" || style.display==="none") return false;
    var r=el.getBoundingClientRect();
    return r.width>0 && r.height>0;
  }
  function setValue(el,value){
    if(!el || !value) return false;
    var current=el.value||"";
    if(current===value) return false;
    if(current && el.getAttribute("data-yc-filled")!=="1") return false;
    var proto=Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,"value");
    if(proto && proto.set){ proto.set.call(el,value); } else { el.value=value; }
    el.setAttribute("data-yc-filled","1");
    el.dispatchEvent(new Event("input",{bubbles:true}));
    el.dispatchEvent(new Event("change",{bubbles:true}));
    try { el.dispatchEvent(new InputEvent("input",{bubbles:true,data:value})); } catch (e) {}
    return true;
  }
  function first(selectors){
    for (var i=0;i<selectors.length;i++){
      var nodes=document.querySelectorAll(selectors[i]);
      for (var j=0;j<nodes.length;j++){
        if(visible(nodes[j])) return nodes[j];
      }
    }
    return null;
  }
  var userInput=first([
    "input#identifierId",
    "input[name=identifier]",
    "input[name=Email]",
    "input[name=email]",
    "input[name=username]",
    "input[name=login]",
    "input[name=uin]",
    "input[name=u]",
    "input#login_field",
    "input#u",
    "input[type=email]",
    "input[autocomplete=username]",
    "input[autocomplete=email]"
  ]);
  var passwordInput=first([
    "input[name=Passwd]",
    "input[name=password]",
    "input[name=p]",
    "input#p",
    "input[type=password]"
  ]);
  if(cred.user) setValue(userInput, cred.user);
  if(cred.password) setValue(passwordInput, cred.password);
  return "1";
})();
''';
}
