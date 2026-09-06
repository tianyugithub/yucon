import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/identity/web_identity.dart';

void main() {
  test('detects google sign-in, captcha and logged-in urls', () {
    expect(
      looksLikeGoogleSignIn(
        'https://accounts.google.com/v3/signin/identifier?dsh=1',
      ),
      isTrue,
    );
    expect(
      looksLikeGoogleCaptcha(
        'https://accounts.google.com/signin/v2/challenge/recaptcha',
      ),
      isTrue,
    );
    expect(
      looksLikeGoogleLoggedIn(
        'https://myaccount.google.com/?utm_source=sign_in',
      ),
      isTrue,
    );
    expect(
      looksLikeGoogleLoggedIn(
        'https://accounts.google.com/v3/signin/identifier',
      ),
      isFalse,
    );
  });

  test('builds restore cookies with google-wide domain', () {
    final snapshot = WebIdentitySnapshot(
      provider: googleIdentityProvider,
      email: 'demo@gmail.com',
      jars: const [
        WebIdentityJar(
          url: 'https://accounts.google.com/',
          header: 'SID=abc; __Host-GAPS=host; APISID=wide',
        ),
      ],
    );
    final cookies = cookiesFromSnapshot(snapshot);
    expect(
      cookies.map((item) => item.name),
      containsAll(['SID', '__Host-GAPS', 'APISID']),
    );
    expect(
      cookies.firstWhere((item) => item.name == 'SID').domain,
      '.google.com',
    );
    expect(
      cookies.firstWhere((item) => item.name == 'APISID').domain,
      '.google.com',
    );
    expect(
      cookies.firstWhere((item) => item.name == '__Host-GAPS').domain,
      isEmpty,
    );
    expect(
      cookies.firstWhere((item) => item.name == 'SID').url,
      'https://accounts.google.com/',
    );
    expect(snapshot.isConnected, isTrue);
    expect(cookies.any((item) => item.name == 'PREF'), isFalse);
  });

  test('nids alone are not a google session', () {
    final snapshot = WebIdentitySnapshot(
      provider: googleIdentityProvider,
      jars: const [
        WebIdentityJar(url: 'https://www.google.com/', header: 'NID=abc'),
      ],
    );
    expect(snapshot.isConnected, isFalse);
    expect(cookiesFromSnapshot(snapshot), isEmpty);
  });

  test('rewrites wide google cookies onto accounts.google.com', () {
    final snapshot = WebIdentitySnapshot(
      provider: googleIdentityProvider,
      jars: const [
        WebIdentityJar(
          url: 'https://www.youtube.com/',
          header: 'SID=from-youtube; PREF=local',
        ),
      ],
    );
    final cookies = cookiesFromSnapshot(snapshot);
    expect(cookies.map((item) => item.name), ['SID']);
    expect(cookies.first.url, 'https://accounts.google.com/');
    expect(cookies.first.domain, '.google.com');
  });

  test('strips webview markers from chrome user agent', () {
    expect(
      chromeLikeUserAgent(
        'Mozilla/5.0 (Linux; Android 16; PKX110; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/144.0.0.0 Mobile Safari/537.36',
      ),
      'Mozilla/5.0 (Linux; Android 16; PKX110) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Mobile Safari/537.36',
    );
  });

  test('detects google cookie error urls', () {
    expect(
      looksLikeGoogleCookieError(
        'https://accounts.google.com/v3/signin/identifier?error=nocookies',
      ),
      isTrue,
    );
  });

  test('parses email from javascript result', () {
    expect(parseGoogleEmailFromJs('"demo@gmail.com"'), 'demo@gmail.com');
    expect(parseGoogleEmailFromJs('null'), isNull);
  });

  test('detects github sign-in, captcha and logged-in urls', () {
    expect(
      looksLikeGitHubSignIn(
        'https://github.com/login?return_to=https%3A%2F%2Fgithub.com%2Fsettings%2Fprofile',
      ),
      isTrue,
    );
    expect(
      looksLikeGitHubSignIn('https://github.com/sessions/two-factor'),
      isTrue,
    );
    expect(
      looksLikeGitHubLoggedIn('https://github.com/settings/profile'),
      isTrue,
    );
    expect(
      looksLikeGitHubLoggedIn('https://github.com/settings/sessions'),
      isTrue,
    );
    expect(looksLikeGitHubLoggedIn('https://github.com/login'), isFalse);
    expect(looksLikeGitHubCaptcha('https://github.com/login?captcha='), isTrue);
  });

  test('builds restore cookies with github-wide domain', () {
    final snapshot = WebIdentitySnapshot(
      provider: githubIdentityProvider,
      email: 'octocat',
      jars: const [
        WebIdentityJar(
          url: 'https://github.com/',
          header: 'user_session=abc; logged_in=yes; __Host-user_session_same_site=host; _octo=skip',
        ),
      ],
    );
    final cookies = cookiesFromSnapshot(snapshot);
    expect(
      cookies.map((item) => item.name),
      containsAll([
        'user_session',
        'logged_in',
        '__Host-user_session_same_site',
      ]),
    );
    expect(cookies.any((item) => item.name == '_octo'), isFalse);
    expect(
      cookies.firstWhere((item) => item.name == 'user_session').domain,
      '.github.com',
    );
    expect(
      cookies.firstWhere((item) => item.name == 'user_session').url,
      'https://github.com/',
    );
    expect(
      cookies
          .firstWhere((item) => item.name == '__Host-user_session_same_site')
          .domain,
      isEmpty,
    );
    expect(snapshot.isConnected, isTrue);
  });

  test('logged_in alone is not a github session', () {
    final snapshot = WebIdentitySnapshot(
      provider: githubIdentityProvider,
      jars: const [
        WebIdentityJar(
          url: 'https://github.com/',
          header: 'logged_in=yes; dotcom_user=octocat',
        ),
      ],
    );
    expect(snapshot.isConnected, isFalse);
  });

  test('parses github login from javascript result', () {
    expect(parseGitHubLoginFromJs('"octocat"'), 'octocat');
    expect(parseGitHubLoginFromJs('null'), isNull);
  });

  test('round-trips identity login accounts', () {
    final account = IdentityLoginAccount(
      id: 'login-1',
      provider: googleIdentityProvider,
      username: 'demo@gmail.com',
      password: 'secret',
    );
    final restored = IdentityLoginAccount.fromJson(account.toJson());
    expect(restored.id, 'login-1');
    expect(restored.provider, googleIdentityProvider);
    expect(restored.username, 'demo@gmail.com');
    expect(restored.password, 'secret');
    expect(restored.canFill, isTrue);
    expect(const IdentityLoginAccount(provider: 'google').isEmpty, isTrue);
  });

  test('migrates legacy one-account-per-provider logins', () {
    final bundle = IdentityLoginBundle.fromJson({
      'google': {'username': 'a@gmail.com', 'password': 'one'},
      'github': {'username': 'octocat', 'password': 'two'},
    });
    expect(bundle.accounts.map((item) => item.username), [
      'a@gmail.com',
      'octocat',
    ]);
    expect(bundle.selectedIds[googleIdentityProvider], 'login-google');
    expect(bundle.selectedIds[githubIdentityProvider], 'login-github');
  });

  test('keeps multiple logins for the same provider', () {
    final bundle = IdentityLoginBundle.fromJson({
      'accounts': [
        {
          'id': 'g1',
          'provider': googleIdentityProvider,
          'username': 'one@gmail.com',
          'password': 'a',
        },
        {
          'id': 'g2',
          'provider': googleIdentityProvider,
          'username': 'two@gmail.com',
          'password': 'b',
        },
        {
          'id': 'h1',
          'provider': githubIdentityProvider,
          'username': 'octocat',
          'password': 'c',
        },
      ],
      'selected': {googleIdentityProvider: 'g2', githubIdentityProvider: 'h1'},
    });
    expect(
      bundle.accounts
          .where((item) => item.provider == googleIdentityProvider)
          .length,
      2,
    );
    expect(bundle.selectedIds[googleIdentityProvider], 'g2');
    final roundTrip = IdentityLoginBundle.fromJson(bundle.toJson());
    expect(roundTrip.accounts.map((item) => item.id), ['g1', 'g2', 'h1']);
    expect(roundTrip.selectedIds[googleIdentityProvider], 'g2');
  });

  test('drops mailbox identity logins from stored bundles', () {
    final bundle = IdentityLoginBundle.fromJson({
      'accounts': [
        {
          'id': 'g1',
          'provider': googleIdentityProvider,
          'username': 'one@gmail.com',
          'password': 'a',
        },
        {
          'id': 'q1',
          'provider': 'qqmail',
          'username': '123456789',
          'password': 'b',
        },
      ],
      'selected': {googleIdentityProvider: 'g1', 'qqmail': 'q1'},
    });
    expect(bundle.accounts.map((item) => item.id), ['g1']);
    expect(bundle.selectedIds.containsKey('qqmail'), isFalse);
    expect(identityGroupTitle(googleIdentityProvider), 'Google');
    expect(identityGroupTitle(githubIdentityProvider), 'GitHub');
    expect(isOAuthIdentityProvider(googleIdentityProvider), isTrue);
    expect(isOAuthIdentityProvider('qqmail'), isFalse);
  });

  test('autofills identity login pages without submitting', () {
    expect(
      shouldAutofillIdentityLogin(
        googleIdentityProvider,
        'https://accounts.google.com/v3/signin/identifier?dsh=1',
      ),
      isTrue,
    );
    expect(
      shouldAutofillIdentityLogin(
        googleIdentityProvider,
        'https://myaccount.google.com/',
      ),
      isFalse,
    );
    expect(
      shouldAutofillIdentityLogin(
        githubIdentityProvider,
        'https://github.com/login',
      ),
      isTrue,
    );
    final script = identityAutofillScript(
      const IdentityLoginAccount(
        provider: googleIdentityProvider,
        username: 'demo@gmail.com',
        password: 'secret',
      ),
    );
    expect(script, contains('demo@gmail.com'));
    expect(script.contains('.click('), isFalse);
    expect(script.contains('submit('), isFalse);
  });

  test('round-trips identity session accountId', () {
    final snapshot = WebIdentitySnapshot(
      provider: googleIdentityProvider,
      accountId: 'login-g1',
      email: 'one@gmail.com',
      jars: const [
        WebIdentityJar(url: 'https://accounts.google.com/', header: 'SID=abc'),
      ],
    );
    final restored = WebIdentitySnapshot.fromJson(snapshot.toJson());
    expect(restored.accountId, 'login-g1');
    expect(restored.email, 'one@gmail.com');
    expect(restored.isConnected, isTrue);
  });

  test('keeps multiple identity sessions keyed by account', () {
    final sessions = {
      'g1': WebIdentitySnapshot(
        provider: googleIdentityProvider,
        accountId: 'g1',
        email: 'one@gmail.com',
        jars: const [
          WebIdentityJar(
            url: 'https://accounts.google.com/',
            header: 'SID=one',
          ),
        ],
      ),
      'g2': WebIdentitySnapshot(
        provider: googleIdentityProvider,
        accountId: 'g2',
        email: 'two@gmail.com',
        jars: const [
          WebIdentityJar(
            url: 'https://accounts.google.com/',
            header: 'SID=two',
          ),
        ],
      ),
    };
    final encoded = {
      for (final entry in sessions.entries) entry.key: entry.value.toJson(),
    };
    final restored = {
      for (final entry in encoded.entries)
        entry.key: WebIdentitySnapshot.fromJson(
          Map<String, dynamic>.from(entry.value),
        ),
    };
    expect(restored['g1']?.email, 'one@gmail.com');
    expect(restored['g2']?.email, 'two@gmail.com');
    expect(restored['g1']?.accountId, 'g1');
    expect(legacyIdentitySessionId(googleIdentityProvider), 'legacy-google');
    expect(legacyIdentitySessionId(githubIdentityProvider), 'legacy-github');
    expect(
      identityWindowTitle(
        googleIdentityProvider,
        login: const IdentityLoginAccount(
          id: 'g1',
          provider: googleIdentityProvider,
          username: 'one@gmail.com',
        ),
      ),
      'one@gmail.com',
    );
    expect(identityProviderTitle(githubIdentityProvider), 'GitHub 登录');
  });

  test('builds site oauth start urls from origin', () {
    expect(
      siteOAuthStartUrls('https://api.example.com/', githubIdentityProvider),
      [
        'https://api.example.com/oauth/github',
        'https://api.example.com/api/oauth/github',
      ],
    );
    expect(
      siteOAuthStartUrls(
        'https://api.example.com',
        googleIdentityProvider,
      ).first,
      'https://api.example.com/oauth/google',
    );
    expect(
      looksLikeIdentityHost(
        'https://accounts.google.com/o/oauth2',
        googleIdentityProvider,
      ),
      isTrue,
    );
    expect(
      looksLikeIdentityHost(
        'https://api.example.com/sign-in',
        googleIdentityProvider,
      ),
      isFalse,
    );
    final script = siteOAuthClickScript(googleIdentityProvider);
    expect(script.contains('.click('), isTrue);
    expect(script.contains('submit('), isFalse);
    expect(script, contains('/auth/oauth/google'));
    expect(script, contains('使用google登录'));
    expect(script, contains('使用google账号登录'));
    expect(script, contains('github.com'));
    expect(script, contains('"wait"'));
    expect(script, contains('dispatchEvent'));
    final github = siteOAuthClickScript(githubIdentityProvider);
    expect(github, contains('使用github登录'));
    expect(github, contains('/auth/oauth/github'));
    expect(
      siteOAuthNavigateScript(
        'https://www.miapi.cc/api/v1/auth/oauth/github/start?redirect=/dashboard',
      ),
      contains('location.assign'),
    );
  });

  test('builds sub2 oauth start urls from origin', () {
    expect(
      siteOAuthStartUrls(
        'https://www.miapi.cc/',
        githubIdentityProvider,
        sub2: true,
      ),
      [
        'https://www.miapi.cc/api/v1/auth/oauth/github/start?redirect=/dashboard',
        'https://www.miapi.cc/api/v1/auth/oauth/github/start',
      ],
    );
    expect(
      siteOAuthStartUrls(
        'https://www.miapi.cc',
        googleIdentityProvider,
        sub2: true,
      ).first,
      'https://www.miapi.cc/api/v1/auth/oauth/google/start?redirect=/dashboard',
    );
    final script = siteOAuthClickScript(githubIdentityProvider);
    expect(script, contains('/auth/oauth/github'));
    expect(script.contains('submit('), isFalse);
  });

  test('matches site hosts without touching public suffixes or identity', () {
    expect(looksLikeSameSiteHost('api.example.com', 'example.com'), isTrue);
    expect(looksLikeSameSiteHost('example.com', 'api.example.com'), isTrue);
    expect(looksLikeSameSiteHost('.example.com', 'api.example.com'), isTrue);
    expect(looksLikeSameSiteHost('example.com', 'google.com'), isFalse);
    expect(looksLikeSameSiteHost('api.example.com', 'com'), isFalse);
    expect(siteOriginOf('https://www.miapi.cc/'), 'https://www.miapi.cc');
    expect(siteOriginOf('www.miapi.cc'), 'https://www.miapi.cc');
    expect(
      siteWebDataOrigins(
        'https://www.miapi.cc',
        extraUrls: const [
          'https://www.miapi.cc/console',
          'https://accounts.google.com',
        ],
      ),
      ['https://www.miapi.cc'],
    );
    expect(
      siteWebDataOrigins(
        'https://api.example.com',
        extraUrls: const ['https://example.com'],
      ),
      containsAll(['https://api.example.com', 'https://example.com']),
    );
  });

  test('classifies identity session probes as alive or expired', () {
    expect(
      classifyIdentityProbeResult(
        provider: githubIdentityProvider,
        url: 'https://github.com/login',
      ),
      IdentitySessionFreshness.expired,
    );
    expect(
      classifyIdentityProbeResult(
        provider: githubIdentityProvider,
        url: 'https://github.com/settings/profile',
      ),
      IdentitySessionFreshness.alive,
    );
    expect(
      classifyIdentityProbeResult(
        provider: googleIdentityProvider,
        url: 'https://accounts.google.com/v3/signin/identifier',
      ),
      IdentitySessionFreshness.expired,
    );
    expect(
      classifyIdentityProbeResult(
        provider: googleIdentityProvider,
        url: 'https://myaccount.google.com/',
      ),
      IdentitySessionFreshness.alive,
    );
    expect(
      classifyIdentityProbeResult(
        provider: googleIdentityProvider,
        url: 'https://accounts.google.com/signin/v2/challenge/recaptcha',
      ),
      IdentitySessionFreshness.unknown,
    );
    expect(
      classifyIdentityProbeResult(
        provider: githubIdentityProvider,
        url: 'https://github.com/settings/profile',
        status: 401,
      ),
      IdentitySessionFreshness.expired,
    );
    expect(
      identitySessionNeedsLogin(IdentitySessionFreshness.expired),
      isTrue,
    );
    expect(
      identitySessionNeedsLogin(IdentitySessionFreshness.alive),
      isFalse,
    );
    expect(
      identitySessionFailureHint(
        googleIdentityProvider,
        IdentitySessionFreshness.missing,
      ),
      contains('请先在身份里登录'),
    );
    expect(
      identitySessionFailureHint(
        githubIdentityProvider,
        IdentitySessionFreshness.alive,
      ),
      isEmpty,
    );
    final snapshot = WebIdentitySnapshot(
      provider: githubIdentityProvider,
      jars: const [
        WebIdentityJar(
          url: 'https://github.com/',
          header: 'user_session=abc; logged_in=yes',
        ),
      ],
    );
    expect(identityCookieHeader(snapshot), contains('user_session=abc'));
  });
}
