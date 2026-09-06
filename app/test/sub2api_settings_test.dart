import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/sub2api.dart';

void main() {
  test('parses wrapped Sub2 public settings and maps site name', () {
    final settings = Sub2PublicSettings.fromJson({
      'code': 0,
      'data': {
        'site_name': '  Demo Sub2  ',
        'turnstile_enabled': true,
      },
    });

    expect(settings.siteName, 'Demo Sub2');
    expect(settings.turnstileEnabled, isTrue);
    expect(siteStatusFromSub2Settings(settings).systemName, 'Demo Sub2');
  });

  test('parses raw Sub2 public settings without data wrapper', () {
    final settings = Sub2PublicSettings.fromJson({
      'site_name': 'Direct Site',
    });

    expect(settings.siteName, 'Direct Site');
    expect(siteStatusFromSub2Settings(settings).systemName, 'Direct Site');
  });

  test('ignores blank Sub2 site names', () {
    final settings = Sub2PublicSettings.fromJson({
      'site_name': '   ',
    });

    expect(settings.siteName, isNull);
    expect(siteStatusFromSub2Settings(settings).systemName, isEmpty);
  });
}
