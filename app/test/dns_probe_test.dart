import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/dns_probe.dart';
import 'package:vault/app/api/http.dart';

void main() {
  test('recognizes GFW sinkhole IPs as DNS poison', () {
    expect(isKnownPoisonAddress(InternetAddress('128.242.240.155')), isTrue);
    expect(isKnownPoisonAddress(InternetAddress('199.16.158.182')), isTrue);
    expect(isKnownPoisonAddress(InternetAddress('198.18.0.34')), isTrue);
    expect(isKnownPoisonAddress(InternetAddress('159.106.121.75')), isTrue);
    expect(isKnownPoisonAddress(InternetAddress('8.214.160.125')), isFalse);
  });

  test('timeouts are treated as site access failures', () {
    expect(looksLikeTransportFailure(ApiError('连接超时，请稍后重试')), isTrue);
    expect(shouldDiagnoseSiteAccess(ApiError('连接超时，请稍后重试')), isTrue);
    expect(userFacingError(ApiError('连接超时，请稍后重试')), kSiteUnreachableMessage);
  });
}
