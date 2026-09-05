import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/modules/vault_store.dart';
import 'package:vault/app/utils/quota.dart';

Account _account({
  required String id,
  required double quota,
  double usedQuota = 0,
  bool excludeFromTotalQuota = false,
}) {
  return Account(
    id: id,
    alias: id,
    siteName: '测试站',
    baseUrl: 'https://example.com',
    platformType: PlatformType.newapi,
    authMode: AuthMode.password,
    userId: '1',
    username: 'demo',
    displayName: 'demo',
    email: '',
    group: 'default',
    quota: quota,
    usedQuota: usedQuota,
    requestCount: 0,
    quotaPerUnit: 500000,
    status: AccountStatus.active,
    checkedInToday: false,
    checkinEnabled: false,
    tags: const [],
    trend: const [],
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
    excludeFromTotalQuota: excludeFromTotalQuota,
  );
}

UsageLog _log({
  required String id,
  required String accountId,
  required double quotaCost,
  required String time,
}) {
  return UsageLog(
    id: id,
    accountId: accountId,
    platformType: PlatformType.newapi,
    apiKeyId: 'k1',
    apiKeyName: '默认',
    model: 'gpt-4',
    time: time,
    quotaCost: quotaCost,
    promptTokens: 1,
    completionTokens: 1,
    success: true,
  );
}

void main() {
  test('totals skip accounts marked excludeFromTotalQuota', () {
    final store = VaultStore();
    addTearDown(store.dispose);
    store.accounts = [
      _account(id: 'kept', quota: 12.5, usedQuota: 3),
      _account(id: 'skipped', quota: 80, usedQuota: 20, excludeFromTotalQuota: true),
    ];

    expect(store.totalQuota, 12.5);
    expect(store.totalUsedQuota, 3);
    expect(store.excludedFromTotalCount, 1);
    expect(store.accounts.length, 2);
  });

  test('today usage skips logs from excluded accounts', () {
    final store = VaultStore();
    addTearDown(store.dispose);
    final now = isoNow();
    store.accounts = [
      _account(id: 'kept', quota: 10),
      _account(id: 'skipped', quota: 10, excludeFromTotalQuota: true),
    ];
    store.usageLogs = [
      _log(id: 'a', accountId: 'kept', quotaCost: 1.25, time: now),
      _log(id: 'b', accountId: 'skipped', quotaCost: 9.5, time: now),
    ];

    expect(store.todayUsage, 1.25);
  });

  test('excludeFromTotalQuota round-trips through json', () {
    final original = _account(id: 'a1', quota: 4, excludeFromTotalQuota: true);
    final restored = Account.fromJson(original.toJson());
    expect(restored.excludeFromTotalQuota, isTrue);

    final legacy = Account.fromJson({
      ...original.toJson()..remove('excludeFromTotalQuota'),
      'excludeFromTotalQuota': null,
    });
    expect(legacy.excludeFromTotalQuota, isFalse);
  });

  test('draft copies excludeFromTotalQuota from an existing account', () {
    final store = VaultStore();
    addTearDown(store.dispose);
    final draft = store.toAccountDraft(
      _account(id: 'a1', quota: 1, excludeFromTotalQuota: true),
    );
    expect(draft.excludeFromTotalQuota, isTrue);
    expect(AccountDraft().excludeFromTotalQuota, isFalse);
  });
}
