import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/utils/app_update.dart';

void main() {
  test('normalizes and compares release tags', () {
    expect(normalizeAppVersion('v0.1.0'), '0.1.0');
    expect(compareAppVersions('0.1.0', '0.1.0'), 0);
    expect(isAppVersionNewer('0.1.1', '0.1.0'), isTrue);
    expect(isAppVersionNewer('0.1.0', '0.1.1'), isFalse);
    expect(isAppVersionNewer('0.2.0', '0.1.9'), isTrue);
  });

  test('parses github latest release assets and notes', () {
    final release = parseGithubRelease({
      'tag_name': 'v0.2.0',
      'name': 'Yucon 钥仓 0.2.0',
      'body': '修复更新检查。',
      'html_url': 'https://github.com/tianyugithub/yucon/releases/tag/v0.2.0',
      'draft': false,
      'assets': [
        {
          'name': 'yucon-vault-0.2.0-android.apk',
          'browser_download_url': 'https://example.com/app.apk',
        },
        {
          'name': 'yucon-vault-0.2.0-ios.ipa',
          'browser_download_url': 'https://example.com/app.ipa',
        },
      ],
    });
    expect(release, isNotNull);
    expect(release!.version, '0.2.0');
    expect(release.notes, '修复更新检查。');
    expect(preferredUpdateUrl(release, android: true), 'https://example.com/app.apk');
    expect(preferredUpdateUrl(release, android: false), release.htmlUrl);
  });

  test('ignores draft releases', () {
    expect(parseGithubRelease({'tag_name': 'v0.3.0', 'draft': true}), isNull);
  });
}
