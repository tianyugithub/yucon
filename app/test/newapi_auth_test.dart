import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';

String _jwt({required int exp}) {
  final header = base64Url.encode(utf8.encode('{"alg":"none"}')).replaceAll('=', '');
  final payload = base64Url.encode(utf8.encode(jsonEncode({'exp': exp}))).replaceAll('=', '');
  return '$header.$payload.sig';
}

void main() {
  test('short-lived NewAPI JWT is treated as stale after expiry', () {
    final expired = _jwt(exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 - 10);
    final fresh = _jwt(exp: DateTime.now().millisecondsSinceEpoch ~/ 1000 + 600);
    expect(newApiAccessTokenIsFresh(expired), isFalse);
    expect(newApiAccessTokenIsFresh(fresh), isTrue);
    expect(newApiAccessTokenIsFresh('cookie:session=abc'), isFalse);
    expect(newApiAccessTokenIsFresh('pat-not-a-jwt-token'), isTrue);
  });

  test('site cookie lookup includes the refresh cookie path', () {
    final urls = cookieUrlsForSite('https://tabitoken.com');
    expect(urls, contains('https://tabitoken.com/api/user/auth/refresh'));
    expect(urls, contains('https://tabitoken.com/api/user/auth'));
  });
}
