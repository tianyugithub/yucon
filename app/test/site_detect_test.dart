import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/api/site_detect.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/quota.dart';

void main() {
  test('recognizes NewAPI /api/status payloads', () {
    expect(
      looksLikeNewApiStatus({
        'success': true,
        'data': {
          'version': 'v0.9.0',
          'start_time': 1710000000,
          'system_name': 'Demo NewAPI',
          'quota_per_unit': 500000,
        },
      }),
      isTrue,
    );
    expect(looksLikeNewApiStatus({'success': true, 'data': {}}), isFalse);
    expect(
      looksLikeNewApiStatus({
        'message': 'ok',
        'data': {'title': 'blog'},
      }),
      isFalse,
    );
  });

  test('recognizes Sub2 public settings payloads', () {
    expect(
      looksLikeSub2Site({
        'code': 0,
        'data': {
          'site_name': 'Demo Sub2',
          'turnstile_enabled': true,
          'github_oauth_enabled': true,
        },
      }),
      isTrue,
    );
    expect(looksLikeSub2Site({'code': 0, 'data': {}}), isFalse);
    expect(looksLikeSub2Site({'foo': 1}), isFalse);
    expect(looksLikeSub2Site({'site_name': 'Only name'}), isTrue);
  });

  test('prefers the stronger fingerprint when both look valid', () {
    final newApi = DetectedSite(
      type: PlatformType.newapi,
      status: SiteStatus(
        quotaPerUnit: defaultQuotaPerUnit,
        checkinEnabled: false,
        systemName: 'New',
      ),
      score: 6,
    );
    final sub2 = DetectedSite(
      type: PlatformType.sub2api,
      status: SiteStatus(
        quotaPerUnit: defaultQuotaPerUnit,
        checkinEnabled: false,
        systemName: 'Sub2',
      ),
      score: 8,
    );
    expect(chooseDetectedSite(newApi, sub2)?.type, PlatformType.sub2api);
    expect(chooseDetectedSite(newApi, null)?.type, PlatformType.newapi);
    expect(chooseDetectedSite(null, sub2)?.type, PlatformType.sub2api);
    expect(chooseDetectedSite(null, null), isNull);
    expect(
      chooseDetectedSite(
        newApi,
        DetectedSite(
          type: PlatformType.sub2api,
          status: sub2.status,
          score: 4,
        ),
      )?.type,
      PlatformType.newapi,
    );
  });
}
