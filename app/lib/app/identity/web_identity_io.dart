import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

const _identityChannel = MethodChannel('cc.yucon.vault/proxy');

Future<void> enableNativeWebViewCookies() async {
  try {
    await _identityChannel.invokeMethod<void>('enableWebViewCookies');
  } catch (_) {}
}

Future<void> resumeAuthWebViews() async {
  try {
    await _identityChannel.invokeMethod<void>('configureChromeWebView');
  } catch (_) {}
}

Future<void> prepareAuthWebView(
  WebViewController controller,
  WebViewCookieManager cookies,
) async {
  await enableNativeWebViewCookies();
  try {
    final ua = chromeLikeUserAgent(await controller.getUserAgent());
    await controller.setUserAgent(ua);
  } catch (_) {
    try {
      await controller.setUserAgent(googleChromeMobileUserAgent);
    } catch (_) {}
  }
  if (defaultTargetPlatform != TargetPlatform.android) {
    return;
  }
  final platform = cookies.platform;
  final view = controller.platform;
  if (platform is AndroidWebViewCookieManager &&
      view is AndroidWebViewController) {
    try {
      await platform.setAcceptThirdPartyCookies(view, true);
    } catch (_) {}
    try {
      await view.setMixedContentMode(MixedContentMode.alwaysAllow);
    } catch (_) {}
  }
  try {
    await _identityChannel.invokeMethod<void>('configureChromeWebView');
  } catch (_) {}
}

Widget authWebView(WebViewController controller) {
  final platform = controller.platform;
  if (platform is AndroidWebViewController) {
    return WebViewWidget.fromPlatform(
      platform: AndroidWebViewWidget(
        AndroidWebViewWidgetCreationParams(
          controller: platform,
          displayWithHybridComposition: true,
        ),
      ),
    );
  }
  return WebViewWidget(controller: controller);
}

Future<void> fillIdentityLogin(
  WebViewController controller,
  IdentityLoginAccount? account,
) async {
  if (account == null || !account.canFill) {
    return;
  }
  try {
    await controller.runJavaScript(identityAutofillScript(account));
  } catch (_) {}
}

Future<void> scrubIdentityWebViewCookies(String provider) async {
  if (provider == githubIdentityProvider) {
    await scrubGitHubWebViewCookies();
    return;
  }
  await scrubGoogleWebViewCookies();
}

Future<void> writeWebViewCookies(List<WebIdentityCookie> cookies) async {
  if (cookies.isEmpty) {
    return;
  }
  try {
    await _identityChannel.invokeMethod<void>('setCookies', {
      'cookies': [for (final cookie in cookies) cookie.toNative()],
    });
  } catch (_) {}
}

Future<void> clearSiteWebViewState(
  String baseUrl, {
  Iterable<String> extraUrls = const [],
}) async {
  final origins = siteWebDataOrigins(baseUrl, extraUrls: extraUrls);
  if (origins.isEmpty) {
    return;
  }
  for (final origin in origins) {
    try {
      await _identityChannel.invokeMethod<void>('clearSiteWebData', {
        'url': origin,
      });
    } catch (_) {}
  }
  final cookies = <WebIdentityCookie>[];
  final seen = <String>{};
  for (final origin in origins) {
    for (final url in cookieUrlsForSite(origin)) {
      String header = '';
      try {
        header = await readWebViewCookieHeader(url);
      } catch (_) {}
      final host = Uri.tryParse(url)?.host ?? Uri.tryParse(origin)?.host ?? '';
      for (final pair in parseCookieHeader(header)) {
        if (pair.$1.trim().isEmpty) {
          continue;
        }
        final domains = <String>{
          '',
          if (!isHostOnlyCookie(pair.$1) && host.isNotEmpty) host,
          if (!isHostOnlyCookie(pair.$1) && host.isNotEmpty) '.$host',
        };
        final dot = host.indexOf('.');
        if (!isHostOnlyCookie(pair.$1) &&
            dot > 0 &&
            host.substring(dot + 1).contains('.')) {
          domains.add(host.substring(dot));
        }
        for (final domain in domains) {
          final key = '$url|$domain|${pair.$1}';
          if (!seen.add(key)) {
            continue;
          }
          cookies.add(
            WebIdentityCookie(
              url: url,
              name: pair.$1,
              value: '',
              domain: domain,
              path: '/',
              secure: true,
              maxAge: -1,
            ),
          );
        }
      }
    }
  }
  await writeWebViewCookies(cookies);
}

Future<void> scrubGoogleWebViewCookies() async {
  final cookies = <WebIdentityCookie>[];
  final seen = <String>{};
  for (final url in googleIdentityCookieUrls) {
    final header = await readWebViewCookieHeader(url);
    for (final pair in parseCookieHeader(header)) {
      if (pair.$1.isEmpty) {
        continue;
      }
      final domains = <String>{
        googleCookieDomainFor(pair.$1, url),
        if (!isGoogleHostCookie(pair.$1)) '.google.com',
        '',
      };
      for (final domain in domains) {
        final cookieUrl = domain == '.google.com'
            ? 'https://accounts.google.com/'
            : url;
        final key = '${domain.isEmpty ? cookieUrl : domain}|${pair.$1}';
        if (!seen.add(key)) {
          continue;
        }
        cookies.add(
          WebIdentityCookie(
            url: cookieUrl,
            name: pair.$1,
            value: pair.$2,
            domain: domain,
            path: '/',
            secure: true,
            maxAge: 0,
          ),
        );
      }
    }
  }
  await writeWebViewCookies(cookies);
}

Future<void> restoreWebIdentityCookies(WebIdentitySnapshot? snapshot) async {
  if (snapshot == null || !snapshot.isConnected) {
    return;
  }
  await writeWebViewCookies(cookiesFromSnapshot(snapshot));
}

Future<void> restoreConnectedIdentityCookies(
  Iterable<WebIdentitySnapshot?> snapshots,
) async {
  for (final snapshot in snapshots) {
    await restoreWebIdentityCookies(snapshot);
  }
}

Future<void> scrubGitHubWebViewCookies() async {
  final cookies = <WebIdentityCookie>[];
  final seen = <String>{};
  for (final url in githubIdentityCookieUrls) {
    final header = await readWebViewCookieHeader(url);
    for (final pair in parseCookieHeader(header)) {
      if (pair.$1.isEmpty) {
        continue;
      }
      final domains = <String>{
        githubCookieDomainFor(pair.$1, url),
        if (!isHostOnlyCookie(pair.$1)) '.github.com',
        '',
      };
      for (final domain in domains) {
        final cookieUrl = domain == '.github.com' ? 'https://github.com/' : url;
        final key = '${domain.isEmpty ? cookieUrl : domain}|${pair.$1}';
        if (!seen.add(key)) {
          continue;
        }
        cookies.add(
          WebIdentityCookie(
            url: cookieUrl,
            name: pair.$1,
            value: pair.$2,
            domain: domain,
            path: '/',
            secure: true,
            maxAge: 0,
          ),
        );
      }
    }
  }
  await writeWebViewCookies(cookies);
}

Future<WebIdentitySnapshot> captureGitHubIdentity({String email = ''}) async {
  final jars = <WebIdentityJar>[];
  for (final url in githubIdentityCookieUrls) {
    final header = githubAuthCookieHeader(await readWebViewCookieHeader(url));
    if (header.trim().isEmpty) {
      continue;
    }
    jars.add(WebIdentityJar(url: url, header: header));
  }
  return WebIdentitySnapshot(
    provider: githubIdentityProvider,
    email: email.trim(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
    jars: jars,
  );
}

Future<void> expireWebIdentityCookies(WebIdentitySnapshot? snapshot) async {
  if (snapshot == null || !snapshot.isConnected) {
    return;
  }
  await writeWebViewCookies(cookiesFromSnapshot(snapshot, maxAge: 0));
}

Future<WebIdentitySnapshot> captureGoogleIdentity({String email = ''}) async {
  final jars = <WebIdentityJar>[];
  for (final url in googleIdentityCookieUrls) {
    final header = googleAuthCookieHeader(await readWebViewCookieHeader(url));
    if (header.trim().isEmpty) {
      continue;
    }
    jars.add(WebIdentityJar(url: url, header: header));
  }
  return WebIdentitySnapshot(
    provider: googleIdentityProvider,
    email: email.trim(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
    jars: jars,
  );
}

Future<IdentitySessionFreshness> probeIdentitySession(
  WebIdentitySnapshot? snapshot,
) async {
  if (snapshot == null || !snapshot.isConnected) {
    return IdentitySessionFreshness.missing;
  }
  final cookie = identityCookieHeader(snapshot);
  if (cookie.isEmpty) {
    return IdentitySessionFreshness.missing;
  }
  try {
    final nav = await probeHttpNavigation(
      identityHomeUrl(snapshot.provider),
      cookie: cookie,
    );
    return classifyIdentityProbeResult(
      provider: snapshot.provider,
      url: nav.url,
      status: nav.status,
    );
  } catch (_) {
    return IdentitySessionFreshness.unknown;
  }
}
