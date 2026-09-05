import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/storage/vault_backup.dart';
import 'package:vault/app/storage/vault_backup_crypto.dart';

Account _account({
  required String id,
  String site = 'https://a.example.com',
  String alias = '账号A',
}) {
  return Account(
    id: id,
    alias: alias,
    siteName: '测试站',
    baseUrl: site,
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
    createdAt: '2026-01-01T00:00:00.000Z',
    updatedAt: '2026-01-01T00:00:00.000Z',
  );
}

VaultSnapshot _snap({
  required List<Account> accounts,
  List<AccountSession>? sessions,
  List<ApiKey>? apiKeys,
  Map<String, String>? revealedKeys,
  Map<String, String>? accountPasswords,
  PrototypeSettings? settings,
}) {
  return VaultSnapshot(
    exportedAt: DateTime.utc(2026, 9, 5, 5, 30),
    accounts: accounts,
    sessions: sessions ??
        [
          for (final account in accounts)
            AccountSession(
              accountId: account.id,
              accessToken: 'token-${account.id}',
              userId: '1',
              cookies: 'session=1',
            ),
        ],
    apiKeys: apiKeys ?? const [],
    revealedKeys: revealedKeys ?? const {},
    accountPasswords: accountPasswords ?? const {},
    checkinLogs: const [],
    usageLogs: const [],
    settings: settings ?? PrototypeSettings(lowQuotaThreshold: 5),
  );
}

void main() {
  test('round-trips accounts, sessions and revealed keys', () {
    final original = _snap(
      accounts: [_account(id: 'a1')],
      apiKeys: [
        ApiKey(
          id: 'k1',
          accountId: 'a1',
          remoteId: 9,
          name: '默认',
          key: 'sk-****',
          keyMasked: true,
          status: ApiKeyStatus.enabled,
          remainQuota: 1,
          usedQuota: 0,
          unlimitedQuota: true,
          createdAt: '2026-01-01T00:00:00.000Z',
          group: 'default',
          modelLimits: const [],
          allowIps: const [],
          crossGroupRetry: false,
        ),
      ],
      revealedKeys: {'k1': 'sk-live-secret'},
      accountPasswords: {'a1': 'site-password'},
    );

    final restored = VaultSnapshot.decode(original.encode());
    expect(restored.accounts.single.id, 'a1');
    expect(restored.sessions.single.accessToken, 'token-a1');
    expect(restored.revealedKeys['k1'], 'sk-live-secret');
    expect(restored.accountPasswords['a1'], 'site-password');
    expect(restored.summaryLabel, contains('1 个登录密码'));
    expect(restored.accounts.single.apiUrls, isEmpty);
  });

  test('rejects unrelated json', () {
    expect(
      () => VaultSnapshot.decode('{"hello":1}'),
      throwsA(isA<VaultBackupException>()),
    );
  });

  test('merge keeps existing accounts and overwrites the same id', () {
    final current = _snap(
      accounts: [_account(id: 'a1', alias: '旧的')],
      settings: PrototypeSettings(lowQuotaThreshold: 3),
    );
    final incoming = _snap(
      accounts: [
        _account(id: 'a1', alias: '新的', site: 'https://b.example.com'),
        _account(id: 'a2', alias: '另一个'),
      ],
      settings: PrototypeSettings(lowQuotaThreshold: 9),
    );

    final merged = VaultSnapshot.merge(current, incoming);
    expect(merged.accounts.map((item) => item.id).toList(), ['a1', 'a2']);
    expect(merged.accounts.first.alias, '新的');
    expect(merged.accounts.first.baseUrl, 'https://b.example.com');
    expect(merged.settings.lowQuotaThreshold, 3);
  });

  test('drops keys that do not belong to an account', () {
    final restored = VaultSnapshot.decode(
      _snap(
        accounts: [_account(id: 'a1')],
        apiKeys: [
          ApiKey(
            id: 'orphan',
            accountId: 'missing',
            remoteId: 1,
            name: '丢弃',
            key: 'sk-x',
            keyMasked: true,
            status: ApiKeyStatus.enabled,
            remainQuota: 0,
            usedQuota: 0,
            unlimitedQuota: true,
            createdAt: '',
            group: 'default',
            modelLimits: const [],
            allowIps: const [],
            crossGroupRetry: false,
          ),
        ],
        revealedKeys: {'orphan': 'secret'},
      ).encode(),
    );
    expect(restored.apiKeys, isEmpty);
    expect(restored.revealedKeys, isEmpty);
  });

  test('encrypted backup round-trips and rejects the wrong password', () async {
    final original = _snap(
      accounts: [_account(id: 'a1')],
      accountPasswords: {'a1': 'login-secret'},
      revealedKeys: {'k1': 'nope'},
    );
    final sealed = await VaultBackupCrypto.seal(original, 'vault-pass');
    expect(peekBackup(sealed).encrypted, isTrue);
    expect(sealed.contains('login-secret'), isFalse);
    expect(sealed.contains('token-a1'), isFalse);

    final opened = await VaultBackupCrypto.open(sealed, password: 'vault-pass');
    expect(opened.accountPasswords['a1'], 'login-secret');
    expect(opened.sessions.single.accessToken, 'token-a1');

    expect(
      () => VaultBackupCrypto.open(sealed, password: 'wrong-pass'),
      throwsA(isA<VaultBackupException>()),
    );
    expect(
      () => VaultSnapshot.decode(sealed),
      throwsA(isA<VaultBackupException>()),
    );
  });

  test('rejects backup passwords shorter than 10 characters', () async {
    final original = _snap(accounts: [_account(id: 'a1')]);
    await expectLater(
      VaultBackupCrypto.seal(original, 'short'),
      throwsA(
        isA<VaultBackupException>().having(
          (error) => error.message,
          'message',
          contains('至少 10'),
        ),
      ),
    );
  });
}
