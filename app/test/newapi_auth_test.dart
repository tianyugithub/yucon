import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';

String _jwt({required int exp}) {
  final header = base64Url
      .encode(utf8.encode('{"alg":"none"}'))
      .replaceAll('=', '');
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'exp': exp})))
      .replaceAll('=', '');
  return '$header.$payload.sig';
}

void main() {
  test('short-lived NewAPI JWT is treated as stale after expiry', () {
    final expired = _jwt(
      exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10,
    );
    final fresh = _jwt(
      exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600,
    );
    expect(newApiAccessTokenIsFresh(expired), isFalse);
    expect(newApiAccessTokenIsFresh(fresh), isTrue);
    expect(newApiAccessTokenIsFresh('cookie:session=abc'), isFalse);
    expect(newApiAccessTokenIsFresh('pat-not-a-jwt-token'), isTrue);
  });

  test('parses site oauth and register flags from status data', () {
    final githubOnly = siteStatusFromData({
      'system_name': 'Demo',
      'quota_per_unit': 500000,
      'github_oauth': true,
      'register_enabled': true,
      'password_login': false,
    });
    expect(githubOnly.systemName, 'Demo');
    expect(githubOnly.githubOAuth, isTrue);
    expect(githubOnly.googleOAuth, isFalse);
    expect(githubOnly.passwordLoginEnabled, isFalse);
    expect(githubOnly.registerEnabled, isTrue);

    final googleOidc = siteStatusFromData({
      'oidc_enabled': true,
      'oidc_issuer': 'https://accounts.google.com',
      'oauth': {'google': true},
    });
    expect(googleOidc.googleOAuth, isTrue);

    final byClientId = siteStatusFromData({
      'github_client_id': 'abc',
      'google_client_id': '123.apps.googleusercontent.com',
    });
    expect(byClientId.githubOAuth, isTrue);
    expect(byClientId.googleOAuth, isTrue);
    expect(byClientId.passwordLoginEnabled, isTrue);
  });

  test('site cookie lookup includes the refresh cookie path', () {
    final urls = cookieUrlsForSite('https://tabitoken.com');
    expect(urls, contains('https://tabitoken.com/api/user/auth/refresh'));
    expect(urls, contains('https://tabitoken.com/api/user/auth'));
  });

  test('login token issue auth uses cookies and ignores model keys', () {
    final fromPrefix = loginTokenIssueAuth('cookie:session=abc', '');
    expect(fromPrefix.cookie, 'session=abc');
    expect(fromPrefix.bearer, isEmpty);

    final fromCookies = loginTokenIssueAuth('', 'session=xyz');
    expect(fromCookies.cookie, 'session=xyz');
    expect(fromCookies.bearer, isEmpty);

    final modelKey = loginTokenIssueAuth('sk-model-key', 'session=keep');
    expect(modelKey.cookie, 'session=keep');
    expect(modelKey.bearer, isEmpty);

    final jwt = loginTokenIssueAuth('eyJhbGciOi.payload.sig', 'session=keep');
    expect(jwt.cookie, 'session=keep');
    expect(jwt.bearer, 'eyJhbGciOi.payload.sig');
  });

  test('issued login token extractor ignores model keys', () {
    expect(
      extractIssuedToken({'data': 'user-login-token'}),
      'user-login-token',
    );
    expect(
      extractIssuedToken({
        'data': {'key': 'sk-model'},
      }),
      isEmpty,
    );
    expect(
      extractIssuedToken({
        'data': {'access_token': 'pat-login'},
      }),
      'pat-login',
    );
  });

  test('visible login access token hides cookie sessions and model keys', () {
    expect(visibleLoginAccessToken(''), isEmpty);
    expect(visibleLoginAccessToken('cookie:session=abc'), isEmpty);
    expect(visibleLoginAccessToken('sk-model-key'), isEmpty);
    expect(visibleLoginAccessToken('pat-login-token'), 'pat-login-token');
  });

  test('checkin path appends turnstile token like login', () {
    expect(newApiCheckinPath(), '/api/user/checkin');
    expect(newApiCheckinPath(turnstileToken: '  '), '/api/user/checkin');
    expect(
      newApiCheckinPath(turnstileToken: 'tok+en'),
      '/api/user/checkin?turnstile=tok%2Ben',
    );
  });

  test('detects newapi turnstile checkin errors', () {
    expect(looksLikeTurnstileRequired(ApiError('Turnstile token 为空')), isTrue);
    expect(
      looksLikeTurnstileRequired(ApiError('Turnstile 校验失败，请刷新重试！')),
      isTrue,
    );
    expect(looksLikeTurnstileRequired(ApiError('请先完成页面上的人机验证后再试。')), isTrue);
    expect(looksLikeTurnstileRequired(ApiError('今日已签到')), isFalse);
  });
}
