import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/format.dart';

Account _account({
  String baseUrl = 'https://panel.example.com',
  List<String> apiUrls = const [],
}) {
  return Account(
    id: 'a1',
    alias: '主账号',
    siteName: '测试站',
    baseUrl: baseUrl,
    platformType: PlatformType.newapi,
    authMode: AuthMode.password,
    userId: '1',
    username: 'demo',
    displayName: 'demo',
    email: '',
    group: 'default',
    quota: 10,
    usedQuota: 0,
    requestCount: 0,
    quotaPerUnit: 500000,
    status: AccountStatus.active,
    checkedInToday: false,
    checkinEnabled: false,
    tags: const [],
    trend: const [],
    createdAt: '',
    updatedAt: '',
    apiUrls: apiUrls,
  );
}

void main() {
  test('copy list defaults to the site address', () {
    expect(
      apiCopyUrlsFor(_account()),
      ['https://panel.example.com'],
    );
  });

  test('appends extra urls and skips the site address duplicate', () {
    final account = _account(
      apiUrls: [
        'https://panel.example.com/',
        'api-backup.example.com',
        'https://api-backup.example.com',
      ],
    );
    expect(apiCopyUrlsFor(account), [
      'https://panel.example.com',
      'https://api-backup.example.com',
    ]);
  });

  test('parses extra urls from a hidden form field', () {
    expect(
      parseExtraApiUrls(
        'https://panel.example.com\napi-2.example.com\n, https://api-3.example.com/',
        baseUrl: 'https://panel.example.com',
      ),
      ['https://api-2.example.com', 'https://api-3.example.com'],
    );
  });

  test('round-trips extra urls on the account json', () {
    final restored = Account.fromJson(
      _account(apiUrls: ['https://api-2.example.com']).toJson(),
    );
    expect(restored.apiUrls, ['https://api-2.example.com']);
  });
}
