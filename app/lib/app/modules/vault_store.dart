import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:vault/app/api/captcha_solver.dart';
import 'package:vault/app/api/dns_probe.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/key_probe.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/api/sub2api.dart';
import 'package:vault/app/constants/model_brands.dart';
import 'package:vault/app/constants/open_source.dart';
import 'package:vault/app/constants/platforms.dart';
import 'package:vault/app/identity/site_register_flow.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/identity/web_identity_io.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/app/storage/vault.dart';
import 'package:vault/app/storage/vault_backup.dart';
import 'package:vault/app/utils/app_update.dart';
import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/model_pricing.dart';
import 'package:vault/app/utils/quota.dart';

const sessionExpiredMessage = '登录已过期，请重新登录';
const sub2QuotaPerUnit = 1.0;

const tokenStatus = <int, ApiKeyStatus>{
  1: ApiKeyStatus.enabled,
  2: ApiKeyStatus.disabled,
  3: ApiKeyStatus.expired,
  4: ApiKeyStatus.exhausted,
};

const sub2KeyStatus = <String, ApiKeyStatus>{
  'active': ApiKeyStatus.enabled,
  'inactive': ApiKeyStatus.disabled,
  'expired': ApiKeyStatus.expired,
  'quota_exhausted': ApiKeyStatus.exhausted,
};

class VaultStore extends ChangeNotifier {
  List<Account> accounts = [];
  List<AccountSession> sessions = [];
  List<ApiKey> apiKeys = [];
  List<CheckinLog> checkinLogs = [];
  List<UsageLog> usageLogs = [];
  Map<String, String> revealedKeys = {};
  Map<String, String> accountPasswords = {};
  PrototypeSettings settings = PrototypeSettings();
  FeedbackState feedback = FeedbackState();
  String searchTerm = '';
  String selectedAccountStatus = 'all';
  String? selectedKeysAccountId;
  bool isRefreshing = false;
  bool hydrated = false;
  int actionCounter = 0;
  AppReleaseInfo? latestRelease;
  bool checkingUpdate = false;
  String? updateCheckError;
  String? _notifiedUpdateVersion;
  final Map<String, List<TokenGroupOption>> tokenGroups = {};
  final Map<String, List<String>> tokenModels = {};
  final Map<String, SitePricingCatalog> pricingCatalogs = {};
  WebIdentitySnapshot? googleIdentity;
  WebIdentitySnapshot? githubIdentity;
  List<IdentityLoginAccount> identityLogins = [];
  Map<String, String> identityLoginSelectedIds = {};
  Map<String, WebIdentitySnapshot> identitySessions = {};
  Timer? _feedbackTimer;

  Account? accountById(String id) {
    for (final account in accounts) {
      if (account.id == id) {
        return account;
      }
    }
    return null;
  }

  AccountSession? sessionByAccount(String accountId) {
    for (final session in sessions) {
      if (session.accountId == accountId) {
        return session;
      }
    }
    return null;
  }

  ApiKey? apiKeyById(String id) {
    for (final apiKey in apiKeys) {
      if (apiKey.id == id) {
        return apiKey;
      }
    }
    return null;
  }

  List<ApiKey> apiKeysForAccount(String accountId) =>
      apiKeys.where((apiKey) => apiKey.accountId == accountId).toList();

  List<UsageLog> usageLogsForAccount(String accountId) {
    return usageLogs.where((log) => log.accountId == accountId).toList()..sort(
      (left, right) =>
          DateTime.parse(right.time).compareTo(DateTime.parse(left.time)),
    );
  }

  String siteLabelForAccount(Account account) {
    final host = hostnameOf(account.baseUrl);
    final name = account.siteName.trim();
    if (name.isNotEmpty &&
        host.isNotEmpty &&
        name.toLowerCase() != host.toLowerCase()) {
      return '$name · $host';
    }
    return host.isNotEmpty
        ? host
        : (name.isNotEmpty
              ? name
              : getPlatformPreset(account.platformType).label);
  }

  String siteLabelForCheckin(CheckinLog log) {
    final account = accountById(log.accountId);
    final host = log.siteHost.trim().isNotEmpty
        ? log.siteHost.trim()
        : (account == null ? '' : hostnameOf(account.baseUrl));
    final name = log.siteName.trim().isNotEmpty
        ? log.siteName.trim()
        : (account?.siteName.trim() ?? '');
    if (name.isNotEmpty &&
        host.isNotEmpty &&
        name.toLowerCase() != host.toLowerCase()) {
      return '$name · $host';
    }
    if (host.isNotEmpty) {
      return host;
    }
    if (name.isNotEmpty) {
      return name;
    }
    return getPlatformPreset(log.platformType).label;
  }

  CheckinLog _checkinLogForAccount({
    required Account account,
    required String id,
    required String time,
    required bool success,
    required String message,
    double? reward,
  }) {
    return CheckinLog(
      id: id,
      accountId: account.id,
      platformType: account.platformType,
      time: time,
      success: success,
      message: message,
      reward: reward,
      siteName: account.siteName,
      siteHost: hostnameOf(account.baseUrl),
    );
  }

  List<T> _keepLatestPerAccount<T>(
    List<T> items,
    String Function(T item) accountIdOf, {
    int limit = 100,
  }) {
    final counts = <String, int>{};
    final kept = <T>[];
    for (final item in items) {
      final id = accountIdOf(item);
      final used = counts[id] ?? 0;
      if (used >= limit) {
        continue;
      }
      counts[id] = used + 1;
      kept.add(item);
    }
    return kept;
  }

  String displayAccountName(Account account) => account.alias.isNotEmpty
      ? account.alias
      : (account.displayName.isNotEmpty
            ? account.displayName
            : (account.username.isNotEmpty ? account.username : '未命名账号'));

  String accountTypeLabel(Account account) =>
      getPlatformPreset(account.platformType).label;

  List<Account> get filteredAccounts {
    final keyword = searchTerm.trim().toLowerCase();
    return accounts.where((account) {
      final matchesKeyword =
          keyword.isEmpty ||
          displayAccountName(account).toLowerCase().contains(keyword) ||
          account.siteName.toLowerCase().contains(keyword) ||
          account.username.toLowerCase().contains(keyword) ||
          account.baseUrl.toLowerCase().contains(keyword) ||
          accountTypeLabel(account).toLowerCase().contains(keyword);
      final matchesStatus =
          selectedAccountStatus == 'all' ||
          account.status.name == selectedAccountStatus;
      return matchesKeyword && matchesStatus;
    }).toList();
  }

  double get totalQuota => roundMoney(
    accounts
        .where((account) => !account.excludeFromTotalQuota)
        .fold<double>(0, (sum, account) => sum + account.quota),
  );

  double get totalUsedQuota => roundMoney(
    accounts
        .where((account) => !account.excludeFromTotalQuota)
        .fold<double>(0, (sum, account) => sum + account.usedQuota),
  );

  int get excludedFromTotalCount =>
      accounts.where((account) => account.excludeFromTotalQuota).length;

  int get totalRequestCount =>
      accounts.fold<int>(0, (sum, account) => sum + account.requestCount);

  double get todayUsage {
    final today = localDateKey(isoNow());
    final excluded = accounts
        .where((account) => account.excludeFromTotalQuota)
        .map((account) => account.id)
        .toSet();
    return roundMoney(
      usageLogs
          .where(
            (log) =>
                localDateKey(log.time) == today &&
                !excluded.contains(log.accountId),
          )
          .fold<double>(0, (sum, log) => sum + log.quotaCost),
    );
  }

  bool isCheckinEligible(Account account) =>
      account.platformType != PlatformType.sub2api &&
      account.checkinEnabled &&
      account.status != AccountStatus.disabled &&
      account.status != AccountStatus.pending &&
      account.status != AccountStatus.expired &&
      account.status != AccountStatus.blocked;

  TodayCheckinStatus get todayCheckinStatus {
    final eligible = accounts.where(isCheckinEligible).toList();
    return TodayCheckinStatus(
      done: eligible.where((account) => account.checkedInToday).length,
      total: eligible.length,
    );
  }

  List<Account> get expiredAccounts => accounts
      .where((account) => account.status == AccountStatus.expired)
      .toList();

  List<Account> get blockedAccounts => accounts
      .where((account) => account.status == AccountStatus.blocked)
      .toList();

  List<Account> get dnsPollutedAccounts =>
      blockedAccounts.where((account) => account.dnsPolluted).toList();

  List<Account> get wafBlockedAccounts =>
      blockedAccounts.where((account) => !account.dnsPolluted).toList();

  List<Account> get lowQuotaAccounts =>
      accounts.where((account) => account.status == AccountStatus.low).toList();

  List<Account> get exhaustedAccounts => accounts
      .where((account) => account.status == AccountStatus.exhausted)
      .toList();

  int get activeApiKeyCount =>
      apiKeys.where((apiKey) => apiKey.status == ApiKeyStatus.enabled).length;

  int keyCountForAccount(String accountId) =>
      apiKeysForAccount(accountId).length;

  bool isCheckedInToday(Account account) =>
      isCheckinEligible(account) && account.checkedInToday;

  List<TokenGroupOption> fallbackGroups(Account? account) {
    final names = <String>{'default'};
    if (account != null && account.group.isNotEmpty) {
      names.add(account.group);
    }
    names.add('auto');
    return names
        .map(
          (name) => TokenGroupOption(
            name: name,
            desc: name == 'auto'
                ? '按系统自动分组规则路由'
                : name == 'default'
                ? '默认分组'
                : '账号分组',
            ratio: name == 'auto' ? null : 1,
            ratioLabel: name == 'auto' ? '自动' : '×1',
          ),
        )
        .toList();
  }

  List<TokenGroupOption> groupsForAccount(Account? account) {
    if (account == null) {
      return [];
    }
    return tokenGroups[account.id] ?? fallbackGroups(account);
  }

  String tokenGroupLabel(String accountId, String groupName) {
    final option = groupsForAccount(accountById(accountId))
        .where((group) => group.name == groupName)
        .firstOrNull;
    if (option == null) {
      return groupName.isEmpty ? 'default' : groupName;
    }
    return '${option.name} · ${option.ratioLabel}';
  }

  String defaultGroupForAccount(Account? account) {
    final groups = groupsForAccount(account);
    if (groups.any((group) => group.name == 'auto')) {
      return 'auto';
    }
    if (account != null &&
        account.group.isNotEmpty &&
        groups.any((group) => group.name == account.group)) {
      return account.group;
    }
    return groups.isEmpty ? 'default' : groups.first.name;
  }

  List<String> modelsForGroup(String accountId, String group) =>
      tokenModels['$accountId:${group.isEmpty ? 'all' : group}'] ?? [];

  bool accountSupportsModelCatalog(Account account) =>
      getPlatformPreset(account.platformType).supportsModelCatalog &&
      account.status != AccountStatus.expired &&
      account.status != AccountStatus.blocked;

  bool get hasPricingCatalogs => pricingCatalogs.isNotEmpty;

  bool get googleIdentityConnected => googleIdentity?.isConnected == true;

  bool get githubIdentityConnected => githubIdentity?.isConnected == true;

  String googleIdentityLabel() => _identityLabel(googleIdentity);

  String githubIdentityLabel() => _identityLabel(githubIdentity);

  List<IdentityLoginAccount> identityLoginsFor(String provider) {
    return [
      for (final account in identityLogins)
        if (account.provider == provider && account.canFill) account,
    ];
  }

  IdentityLoginAccount? identityLoginFor(String provider) {
    final items = identityLoginsFor(provider);
    if (items.isEmpty) {
      return null;
    }
    final selectedId = identityLoginSelectedIds[provider];
    for (final account in items) {
      if (account.id == selectedId) {
        return account;
      }
    }
    return items.first;
  }

  String identityLoginLabel(String provider) {
    final items = identityLoginsFor(provider);
    if (items.isEmpty) {
      return '未保存';
    }
    if (items.length == 1) {
      return items.first.label;
    }
    return '${items.length} 个';
  }

  String identityLoginSubtitle(String provider) {
    final items = identityLoginsFor(provider);
    if (items.length > 1) {
      final selected = identityLoginFor(provider);
      final name = selected?.label ?? '';
      return name.isEmpty ? '可保存多个，登录页填入当前选中的账号' : '当前填入 $name';
    }
    return '可保存多个，登录页自动填入，登录需手动点';
  }

  String identitySessionKey(String provider, {String? accountId}) {
    final id = (accountId ?? '').trim();
    if (id.isNotEmpty) {
      return id;
    }
    final selected = identityLoginFor(provider)?.id.trim() ?? '';
    if (selected.isNotEmpty) {
      return selected;
    }
    return legacyIdentitySessionId(provider);
  }

  WebIdentitySnapshot? identitySessionFor(String? accountId) {
    final id = (accountId ?? '').trim();
    if (id.isEmpty) {
      return null;
    }
    final snapshot = identitySessions[id];
    return snapshot?.isConnected == true ? snapshot : null;
  }

  WebIdentitySnapshot? identitySessionForProvider(String provider) {
    return identitySessionFor(identitySessionKey(provider));
  }

  bool identityWindowConnected(String provider, {String? accountId}) =>
      identitySessionFor(identitySessionKey(provider, accountId: accountId))
          ?.isConnected ==
      true;

  String identityWindowLabel(String provider, {String? accountId}) =>
      _identityLabel(
        identitySessionFor(identitySessionKey(provider, accountId: accountId)),
      );

  void _refreshProviderIdentityFields() {
    googleIdentity = identitySessionForProvider(googleIdentityProvider);
    githubIdentity = identitySessionForProvider(githubIdentityProvider);
  }

  Future<void> _persistIdentityState() async {
    _refreshProviderIdentityFields();
    await Future.wait([
      VaultStorage.saveIdentitySessions(identitySessions),
      VaultStorage.saveGoogleIdentity(googleIdentity),
      VaultStorage.saveGitHubIdentity(githubIdentity),
      VaultStorage.saveIdentityLogins(_identityLoginBundle()),
    ]);
    _bump();
  }

  Future<void> rememberIdentityLogin(IdentityLoginAccount account) async {
    var next = account;
    if (next.provider.isEmpty) {
      return;
    }
    if (next.isEmpty) {
      if (next.id.isNotEmpty) {
        await forgetIdentityLogin(next.id);
      }
      return;
    }
    if (next.id.isEmpty) {
      final username = next.username.trim().toLowerCase();
      for (final existing in identityLogins) {
        if (existing.provider == next.provider &&
            existing.username.trim().toLowerCase() == username) {
          next = next.copyWith(id: existing.id);
          break;
        }
      }
    }
    if (next.id.isEmpty) {
      next = next.copyWith(id: makeId('login'));
    }
    final index = identityLogins.indexWhere((item) => item.id == next.id);
    if (index >= 0) {
      identityLogins[index] = next;
    } else {
      identityLogins = [...identityLogins, next];
    }
    identityLoginSelectedIds[next.provider] = next.id;
    _adoptLegacySession(next);
    await _persistIdentityState();
  }

  Future<void> selectIdentityLogin(String provider, String id) async {
    if (provider.isEmpty || id.isEmpty) {
      return;
    }
    identityLoginSelectedIds[provider] = id;
    await _persistIdentityState();
  }

  Future<void> forgetIdentityLogin(String id) async {
    if (id.isEmpty) {
      return;
    }
    IdentityLoginAccount? removed;
    for (final account in identityLogins) {
      if (account.id == id) {
        removed = account;
        break;
      }
    }
    identityLogins = [
      for (final account in identityLogins)
        if (account.id != id) account,
    ];
    identityLoginSelectedIds.removeWhere(
      (provider, selected) => selected == id,
    );
    final previous = identitySessions.remove(id);
    final provider = (previous?.provider ?? removed?.provider ?? '').trim();
    await expireWebIdentityCookies(previous);
    if (provider.isNotEmpty) {
      try {
        await scrubIdentityWebViewCookies(provider);
        final keepId =
            identityLoginSelectedIds[provider] ??
            (identityLoginsFor(provider).isEmpty
                ? ''
                : identityLoginsFor(provider).first.id);
        if (keepId.isNotEmpty) {
          await restoreWebIdentityCookies(identitySessionFor(keepId));
        }
      } catch (_) {}
    }
    await _persistIdentityState();
  }

  IdentityLoginBundle _identityLoginBundle() => IdentityLoginBundle(
    accounts: identityLogins,
    selectedIds: identityLoginSelectedIds,
  );

  void _adoptLegacySession(IdentityLoginAccount account) {
    if (identitySessionFor(account.id) != null) {
      return;
    }
    final legacy = identitySessions[legacyIdentitySessionId(account.provider)];
    if (legacy?.isConnected != true) {
      return;
    }
    final email = account.username.trim().toLowerCase();
    final legacyEmail = legacy!.email.trim().toLowerCase();
    final onlyOne = identityLoginsFor(account.provider).length == 1;
    if (onlyOne ||
        (email.isNotEmpty &&
            (legacyEmail == email || legacyEmail.contains(email)))) {
      identitySessions[account.id] = legacy.copyWith(accountId: account.id);
      identitySessions.remove(legacyIdentitySessionId(account.provider));
    }
  }

  void _migrateLegacyIdentitySession(
    String provider,
    WebIdentitySnapshot? snapshot,
  ) {
    if (snapshot?.isConnected != true) {
      return;
    }
    if (identitySessions.values.any(
      (item) => item.provider == provider && item.isConnected,
    )) {
      return;
    }
    final email = snapshot!.email.trim().toLowerCase();
    final logins = identityLoginsFor(provider);
    String? key;
    for (final login in logins) {
      final username = login.username.trim().toLowerCase();
      if (username.isNotEmpty &&
          (email == username ||
              email.contains(username) ||
              username.contains(email))) {
        key = login.id;
        break;
      }
    }
    key ??= logins.length == 1 ? logins.first.id : null;
    key ??= legacyIdentitySessionId(provider);
    identitySessions[key] = snapshot.copyWith(accountId: key);
  }

  String identitySummaryLabel() {
    final items = <String>[
      for (final snapshot in identitySessions.values)
        if (snapshot.isConnected) snapshot.label,
    ];
    return items.isEmpty ? '未连接' : items.toSet().join(' · ');
  }

  String _identityLabel(WebIdentitySnapshot? identity) {
    if (identity == null || !identity.isConnected) {
      return '未连接';
    }
    final email = identity.email.trim();
    return email.isEmpty ? '已记住' : email;
  }

  String siteHostForAccount(Account account) =>
      hostnameOf(account.baseUrl).trim().toLowerCase();

  bool _accountMatchesSite(Account account, String? siteHost) {
    if (siteHost == null || siteHost.trim().isEmpty) {
      return true;
    }
    return siteHostForAccount(account) == siteHost.trim().toLowerCase();
  }

  Future<void> _persistPricingCatalogs() =>
      VaultStorage.savePricingCatalogs(pricingCatalogs);

  Future<void> _persistTokenGroupCache() =>
      VaultStorage.saveTokenGroupCache(tokenGroups);

  Future<void> _persistTokenModelCache() =>
      VaultStorage.saveTokenModelCache(tokenModels);

  Future<void> rememberIdentitySession(
    WebIdentitySnapshot snapshot, {
    String? accountId,
  }) async {
    final id = identitySessionKey(
      snapshot.provider,
      accountId: (accountId ?? snapshot.accountId).trim(),
    );
    final next = snapshot.copyWith(accountId: id);
    if (next.isConnected) {
      identitySessions[id] = next;
    } else {
      identitySessions.remove(id);
    }
    await restoreWebIdentityCookies(next.isConnected ? next : null);
    await _persistIdentityState();
  }

  Future<void> forgetIdentitySession(
    String provider, {
    String? accountId,
  }) async {
    final id = identitySessionKey(provider, accountId: accountId);
    final previous = identitySessions.remove(id);
    await expireWebIdentityCookies(previous);
    await _persistIdentityState();
  }

  Future<IdentitySessionFreshness> verifyIdentitySession(
    String provider, {
    String? accountId,
    NetworkProxy? proxy,
  }) async {
    final id = identitySessionKey(provider, accountId: accountId);
    final snapshot = identitySessionFor(id);
    if (snapshot == null || !snapshot.isConnected) {
      return IdentitySessionFreshness.missing;
    }
    final fresh = await runWithProxy(
      proxy ?? resolvedProxy(settings.networkProxy),
      () => probeIdentitySession(snapshot),
    );
    if (fresh == IdentitySessionFreshness.expired) {
      await forgetIdentitySession(provider, accountId: id);
    }
    return fresh;
  }

  Future<void> rememberGoogleIdentity(
    WebIdentitySnapshot snapshot, {
    String? accountId,
  }) => rememberIdentitySession(
    snapshot.copyWith(provider: googleIdentityProvider),
    accountId: accountId,
  );

  Future<void> forgetGoogleIdentity({String? accountId}) =>
      forgetIdentitySession(googleIdentityProvider, accountId: accountId);

  Future<void> rememberGitHubIdentity(
    WebIdentitySnapshot snapshot, {
    String? accountId,
  }) => rememberIdentitySession(
    snapshot.copyWith(provider: githubIdentityProvider),
    accountId: accountId,
  );

  Future<void> forgetGitHubIdentity({String? accountId}) =>
      forgetIdentitySession(githubIdentityProvider, accountId: accountId);

  Future<SitePricingCatalog?> loadPricingCatalog(
    String accountId, {
    bool persistCatalogs = true,
  }) async {
    final account = accountById(accountId);
    if (account == null || !accountSupportsModelCatalog(account)) {
      if (pricingCatalogs.remove(accountId) != null && persistCatalogs) {
        await _persistPricingCatalogs();
      }
      _bump();
      return pricingCatalogs[accountId];
    }
    try {
      final catalog = await withAccountAuth(account, (session) async {
        final pricingFuture = fetchSitePricing(
          account.baseUrl,
          session.accessToken,
          session.userId,
        );
        final modelsFuture = () async {
          try {
            return await fetchGroupModels(
              account.baseUrl,
              session.accessToken,
              session.userId,
              '',
            );
          } catch (_) {
            return <String>[];
          }
        }();
        final pricing = await pricingFuture;
        final models = await modelsFuture;
        if (models.isNotEmpty) {
          tokenModels['$accountId:all'] = models;
        }
        return pricing.filteredToModels(models);
      });
      if (catalog.isEmpty) {
        pricingCatalogs.remove(accountId);
        if (persistCatalogs) {
          await _persistPricingCatalogs();
        }
        _bump();
        return null;
      }
      pricingCatalogs[accountId] = catalog;
      if (persistCatalogs) {
        await _persistPricingCatalogs();
        await _persistTokenModelCache();
      }
      _bump();
      return catalog;
    } catch (error) {
      if (isAuthExpiredError(error)) {
        rethrow;
      }
      return pricingCatalogs[accountId];
    }
  }

  Future<void> loadAllPricingCatalogs({bool force = false}) async {
    final targets = accounts.where(accountSupportsModelCatalog).toList();
    var changed = force;
    await Future.wait(
      targets.map((account) async {
        if (!force && pricingCatalogs.containsKey(account.id)) {
          return;
        }
        changed = true;
        try {
          await loadPricingCatalog(account.id, persistCatalogs: false);
        } catch (_) {}
      }),
    );
    if (changed) {
      await _persistPricingCatalogs();
      await _persistTokenModelCache();
    }
  }

  Set<String> _comparableModelNameSet({
    String query = '',
    String? brandKey,
    String? siteHost,
    bool useAccountGroup = false,
  }) {
    final keyword = query.trim().toLowerCase();
    final names = <String>{};
    for (final account in accounts) {
      if (!accountSupportsModelCatalog(account) ||
          !_accountMatchesSite(account, siteHost)) {
        continue;
      }
      final catalog = pricingCatalogs[account.id];
      if (catalog == null) {
        continue;
      }
      final priced = enrichCatalogGroups(catalog, groupsForAccount(account));
      for (final quote in priced.quotes) {
        final offers = offersForAccountModel(
          account: account,
          quote: quote,
          catalog: priced,
        );
        if (pickOfferForAccount(
              account: account,
              offers: offers,
              useAccountGroup: useAccountGroup,
            ) ==
            null) {
          continue;
        }
        if (keyword.isNotEmpty &&
            !quote.modelName.toLowerCase().contains(keyword)) {
          continue;
        }
        if (brandKey != null &&
            brandKey.isNotEmpty &&
            detectModelBrand(quote.modelName).key != brandKey) {
          continue;
        }
        names.add(quote.modelName);
      }
    }
    return names;
  }

  List<(String, String)> comparableSites() {
    final labels = <String, String>{};
    for (final account in accounts) {
      if (!accountSupportsModelCatalog(account) ||
          pricingCatalogs[account.id] == null) {
        continue;
      }
      final host = siteHostForAccount(account);
      if (host.isEmpty) {
        continue;
      }
      labels.putIfAbsent(host, () {
        final name = account.siteName.trim();
        final displayHost = hostnameOf(account.baseUrl);
        if (name.isNotEmpty &&
            name.toLowerCase() != displayHost.toLowerCase()) {
          return name;
        }
        return displayHost.isNotEmpty ? displayHost : name;
      });
    }
    final list = labels.entries.toList()
      ..sort(
        (left, right) =>
            left.value.toLowerCase().compareTo(right.value.toLowerCase()),
      );
    return [for (final entry in list) (entry.key, entry.value)];
  }

  List<(String, ModelCompareOffer, int)> comparableModelSummaries({
    String query = '',
    String? brandKey,
    String? siteHost,
    bool useAccountGroup = false,
  }) {
    final names = _comparableModelNameSet(
      query: query,
      brandKey: brandKey,
      siteHost: siteHost,
      useAccountGroup: useAccountGroup,
    );
    final lowest = <String, ModelCompareOffer>{};
    final siteIds = <String, Set<String>>{};
    for (final account in accounts) {
      if (!accountSupportsModelCatalog(account) ||
          !_accountMatchesSite(account, siteHost)) {
        continue;
      }
      final catalog = pricingCatalogForAccount(account);
      if (catalog == null) {
        continue;
      }
      for (final quote in catalog.quotes) {
        if (!names.contains(quote.modelName)) {
          continue;
        }
        final offers = offersForAccountModel(
          account: account,
          quote: quote,
          catalog: catalog,
        );
        final offer = pickOfferForAccount(
          account: account,
          offers: offers,
          useAccountGroup: useAccountGroup,
        );
        if (offer == null) {
          continue;
        }
        siteIds.putIfAbsent(quote.modelName, () => {}).add(account.id);
        final current = lowest[quote.modelName];
        if (current == null || compareModelOffers(offer, current) < 0) {
          lowest[quote.modelName] = offer;
        }
      }
    }
    final list = names.where((name) => lowest.containsKey(name)).toList();
    list.sort((left, right) {
      final cmp = compareModelOffers(lowest[left]!, lowest[right]!);
      if (cmp != 0) {
        return cmp;
      }
      return left.toLowerCase().compareTo(right.toLowerCase());
    });
    return [
      for (final name in list)
        (name, lowest[name]!, siteIds[name]?.length ?? 0),
    ];
  }

  List<String> comparableModelNames({
    String query = '',
    String? brandKey,
    String? siteHost,
    bool useAccountGroup = false,
  }) => comparableModelSummaries(
    query: query,
    brandKey: brandKey,
    siteHost: siteHost,
    useAccountGroup: useAccountGroup,
  ).map((item) => item.$1).toList();

  List<ModelBrand> comparableBrands({
    String query = '',
    String? siteHost,
    bool useAccountGroup = false,
  }) {
    final seen = <String, ModelBrand>{};
    for (final name in _comparableModelNameSet(
      query: query,
      siteHost: siteHost,
      useAccountGroup: useAccountGroup,
    )) {
      final brand = detectModelBrand(name);
      seen[brand.key] = brand;
    }
    final list = seen.values.toList()
      ..sort((left, right) {
        if (left.key == 'unknown') {
          return 1;
        }
        if (right.key == 'unknown') {
          return -1;
        }
        return left.label.compareTo(right.label);
      });
    return list;
  }

  SitePricingCatalog? pricingCatalogForAccount(Account account) {
    final catalog = pricingCatalogs[account.id];
    if (catalog == null) {
      return null;
    }
    return enrichCatalogGroups(catalog, groupsForAccount(account));
  }

  List<ModelCompareOffer> offersForModel(String modelName, {String? siteHost}) {
    final offers = <ModelCompareOffer>[];
    for (final account in accounts) {
      if (!accountSupportsModelCatalog(account) ||
          !_accountMatchesSite(account, siteHost)) {
        continue;
      }
      final catalog = pricingCatalogForAccount(account);
      if (catalog == null) {
        continue;
      }
      final quote = catalog.quotes
          .where((item) => item.modelName == modelName)
          .firstOrNull;
      if (quote == null) {
        continue;
      }
      offers.addAll(
        offersForAccountModel(account: account, quote: quote, catalog: catalog),
      );
    }
    sortModelCompareOffers(offers);
    return offers;
  }

  List<(Account, List<ModelCompareOffer>)> sitesForModel(
    String modelName, {
    String? siteHost,
    bool useAccountGroup = false,
  }) {
    final grouped = <String, List<ModelCompareOffer>>{};
    for (final offer in offersForModel(modelName, siteHost: siteHost)) {
      grouped.putIfAbsent(offer.accountId, () => []).add(offer);
    }
    final sites = <(Account, List<ModelCompareOffer>, ModelCompareOffer)>[];
    for (final entry in grouped.entries) {
      final account = accountById(entry.key);
      final groups = entry.value;
      if (account == null || groups.isEmpty) {
        continue;
      }
      sortModelCompareOffers(groups);
      final view = pickOfferForAccount(
        account: account,
        offers: groups,
        useAccountGroup: useAccountGroup,
      );
      if (view == null) {
        continue;
      }
      sites.add((account, groups, view));
    }
    sites.sort((left, right) {
      final cmp = compareModelOffers(left.$3, right.$3);
      if (cmp != 0) {
        return cmp;
      }
      return displayAccountName(left.$1)
          .compareTo(displayAccountName(right.$1));
    });
    return [for (final site in sites) (site.$1, site.$2)];
  }

  bool _deferPersist = false;
  bool _usageDirty = false;

  Future<void> persist() async {
    if (_deferPersist) {
      return;
    }
    await Future.wait([
      VaultStorage.saveAccounts(accounts),
      VaultStorage.saveSessions(sessions),
      VaultStorage.saveApiKeys(apiKeys),
      VaultStorage.saveCheckinLogs(checkinLogs),
      if (_usageDirty) VaultStorage.saveUsageLogs(usageLogs),
      VaultStorage.saveSettings(settings),
      VaultStorage.saveRevealedKeys(revealedKeys),
      VaultStorage.saveAccountPasswords(accountPasswords),
      VaultStorage.saveProxySecrets(_proxySecretsFromState()),
      VaultStorage.saveGoogleIdentity(googleIdentity),
      VaultStorage.saveGitHubIdentity(githubIdentity),
      VaultStorage.saveIdentityLogins(_identityLoginBundle()),
      VaultStorage.saveIdentitySessions(identitySessions),
    ]);
    _usageDirty = false;
  }

  Future<T> _withDeferredPersist<T>(Future<T> Function() run) async {
    _deferPersist = true;
    try {
      return await run();
    } finally {
      _deferPersist = false;
      await persist();
    }
  }

  ProxySecrets _proxySecretsFromState() {
    final solver = settings.captchaSolver;
    return ProxySecrets(
      global: settings.networkProxy.password,
      captcha: solver.clientKey,
      captchaKeys: {
        for (final type in CaptchaSolverType.values)
          if (solver.keyFor(type).isNotEmpty) type.name: solver.keyFor(type),
      },
      accounts: {
        for (final account in accounts)
          if (account.proxy.password.isNotEmpty)
            account.id: account.proxy.password,
      },
    );
  }

  void _applyProxySecrets(ProxySecrets secrets) {
    if (secrets.global.isNotEmpty) {
      settings.networkProxy.password = secrets.global;
    }
    if (secrets.captchaKeys.isNotEmpty) {
      for (final entry in secrets.captchaKeys.entries) {
        final type = tryCaptchaSolverType(entry.key);
        if (type != null && entry.value.isNotEmpty) {
          settings.captchaSolver.setKey(type, entry.value);
        }
      }
    }
    if (secrets.captcha.isNotEmpty &&
        settings.captchaSolver.clientKey.isEmpty) {
      settings.captchaSolver.clientKey = secrets.captcha;
    }
    for (final account in accounts) {
      final password = secrets.accounts[account.id];
      if (password != null && password.isNotEmpty) {
        account.proxy.password = password;
      }
    }
  }

  void _rememberPassword(String accountId, String password) {
    if (accountId.isEmpty || password.isEmpty) {
      return;
    }
    accountPasswords[accountId] = password;
  }

  String passwordForAccount(String accountId) {
    return accountPasswords[accountId] ?? '';
  }

  VaultSnapshot captureSnapshot() {
    return VaultSnapshot(
      exportedAt: DateTime.now().toUtc(),
      accounts: accounts,
      sessions: sessions,
      apiKeys: apiKeys,
      revealedKeys: revealedKeys,
      accountPasswords: accountPasswords,
      checkinLogs: checkinLogs,
      usageLogs: usageLogs,
      settings: settings,
      identityLogins: identityLogins,
      identityLoginSelectedIds: identityLoginSelectedIds,
      identitySessions: identitySessions,
    ).clone();
  }

  Future<VaultSnapshot> applySnapshot(
    VaultSnapshot snapshot, {
    required VaultBackupApplyMode mode,
  }) async {
    final next = mode == VaultBackupApplyMode.replace
        ? snapshot.clone()
        : VaultSnapshot.merge(captureSnapshot(), snapshot);
    accounts = next.accounts;
    sessions = next.sessions;
    apiKeys = next.apiKeys;
    revealedKeys = Map<String, String>.from(next.revealedKeys);
    accountPasswords = Map<String, String>.from(next.accountPasswords);
    checkinLogs = next.checkinLogs;
    usageLogs = next.usageLogs;
    _usageDirty = true;
    settings = next.settings.copyWith();
    identityLogins = [
      for (final account in next.identityLogins)
        if (isOAuthIdentityProvider(account.provider) && !account.isEmpty)
          account,
    ];
    identityLoginSelectedIds = Map<String, String>.from(
      next.identityLoginSelectedIds,
    );
    identitySessions = {
      for (final entry in next.identitySessions.entries)
        if (entry.value.isConnected &&
            isOAuthIdentityProvider(entry.value.provider))
          entry.key: entry.value,
    };
    _refreshProviderIdentityFields();
    final liveIds = accounts.map((account) => account.id).toSet();
    if (selectedKeysAccountId != null &&
        !liveIds.contains(selectedKeysAccountId)) {
      selectedKeysAccountId = liveIds.isEmpty ? null : liveIds.first;
    }
    tokenGroups.removeWhere((accountId, _) => !liveIds.contains(accountId));
    tokenModels.removeWhere((key, _) {
      final accountId = key.contains(':') ? key.split(':').first : key;
      return !liveIds.contains(accountId);
    });
    pricingCatalogs.removeWhere((accountId, _) => !liveIds.contains(accountId));
    accountPasswords.removeWhere(
      (accountId, password) => !liveIds.contains(accountId) || password.isEmpty,
    );
    HttpRequestLogger.instance.setEnabled(settings.developerLogEnabled);
    await persist();
    await restoreConnectedIdentityCookies(identitySessions.values);
    await _persistPricingCatalogs();
    await _persistTokenGroupCache();
    await _persistTokenModelCache();
    _bump();
    return next;
  }

  void _bump() => notifyListeners();

  String makeId(String prefix) {
    actionCounter += 1;
    return '$prefix-${DateTime.now().millisecondsSinceEpoch}-$actionCounter';
  }

  void updateAccountStatus(Account account) {
    if (account.status == AccountStatus.pending ||
        account.status == AccountStatus.disabled ||
        account.status == AccountStatus.expired ||
        account.status == AccountStatus.blocked) {
      return;
    }
    if (account.quota <= 0) {
      account.status = AccountStatus.exhausted;
      return;
    }
    account.status = account.quota < settings.lowQuotaThreshold
        ? AccountStatus.low
        : AccountStatus.active;
  }

  void appendTrendPoint(Account account) {
    final now = isoNow();
    final point = BalancePoint(label: weekdayLabel(now), value: account.quota);
    if (account.trend.isNotEmpty &&
        localDateKey(account.updatedAt) == localDateKey(now)) {
      account.trend = [
        ...account.trend.sublist(0, account.trend.length - 1),
        point,
      ];
      return;
    }
    final start = account.trend.length > 6 ? account.trend.length - 6 : 0;
    account.trend = [...account.trend.sublist(start), point];
  }

  void applyUserSnapshot(Account account, NewApiUser user) {
    account.userId = '${user.id}';
    final nextUsername = user.username ?? account.username;
    if (!keepMailboxLoginIdentity(account.username, nextUsername)) {
      account.username = nextUsername;
    }
    account.displayName = user.displayName ?? account.displayName;
    final nextEmail = (user.email ?? '').trim();
    if (nextEmail.isNotEmpty) {
      account.email = nextEmail;
    } else if (account.email.trim().isEmpty &&
        isMailboxLoginIdentity(account.username)) {
      account.email = account.username.trim();
    }
    account.group = user.group ?? 'default';
    account.quota = quotaToMoney(user.quota, account.quotaPerUnit);
    account.usedQuota = quotaToMoney(user.usedQuota, account.quotaPerUnit);
    account.requestCount = user.requestCount;
    account.updatedAt = isoNow();
    account.lastSyncedAt = account.updatedAt;
    account.lastError = null;
    if (user.status != 1) {
      account.status = AccountStatus.disabled;
      return;
    }
    account.status = AccountStatus.active;
    appendTrendPoint(account);
    updateAccountStatus(account);
  }

  ApiKey mapToken(Account account, NewApiToken token) {
    final id = '${account.id}:${token.id}';
    final revealed = revealedKeys[id];
    final rawKey = revealed ?? token.key ?? '';
    final expiredAt = token.expiredTime != null && token.expiredTime! > 0
        ? unixToIso(token.expiredTime)
        : null;
    return ApiKey(
      id: id,
      accountId: account.id,
      remoteId: token.id,
      name: token.name?.isNotEmpty == true ? token.name! : '未命名密钥',
      key: rawKey,
      keyMasked: revealed == null && isMaskedKey(rawKey),
      status: tokenStatus[token.status] ?? ApiKeyStatus.enabled,
      remainQuota: quotaToMoney(token.remainQuota, account.quotaPerUnit),
      usedQuota: quotaToMoney(token.usedQuota, account.quotaPerUnit),
      unlimitedQuota: token.unlimitedQuota,
      expiresAt: expiredAt,
      createdAt: unixToIso(token.createdTime) ?? isoNow(),
      accessedAt: unixToIso(token.accessedTime),
      group: token.group?.isNotEmpty == true ? token.group! : 'default',
      modelLimits:
          token.modelLimits
              ?.split(',')
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          [],
      allowIps:
          token.allowIps
              ?.split(RegExp(r'[\n,]'))
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList() ??
          [],
      crossGroupRetry: token.crossGroupRetry,
    );
  }

  ApiKey mapSub2Key(Account account, Sub2Key token) {
    final id = '${account.id}:${token.id}';
    final revealed = revealedKeys[id];
    final rawKey = revealed ?? token.key ?? '';
    final quota = token.quota;
    final used = token.quotaUsed;
    final unlimited = !quota.isFinite || quota <= 0;
    return ApiKey(
      id: id,
      accountId: account.id,
      remoteId: token.id,
      name: token.name?.isNotEmpty == true ? token.name! : '未命名密钥',
      key: rawKey,
      keyMasked: revealed == null && isMaskedKey(rawKey),
      status: sub2KeyStatus[token.status] ?? ApiKeyStatus.enabled,
      remainQuota: unlimited
          ? 0
          : roundMoney((quota - used).clamp(0, double.infinity)),
      usedQuota: roundMoney(used),
      unlimitedQuota: unlimited,
      expiresAt: token.expiresAt,
      createdAt: token.createdAt ?? isoNow(),
      accessedAt: token.lastUsedAt,
      group: token.groupName?.isNotEmpty == true
          ? token.groupName!
          : (token.groupId != null
                ? '${token.groupId}'
                : defaultGroupForAccount(account)),
      modelLimits: const [],
      allowIps: token.ipWhitelist,
      crossGroupRetry: false,
    );
  }

  void applySub2UserSnapshot(
    Account account,
    Sub2User user, {
    double? usedQuota,
    int? requestCount,
  }) {
    account.userId = '${user.id}';
    final nextUsername = user.username ?? account.username;
    if (!keepMailboxLoginIdentity(account.username, nextUsername)) {
      account.username = nextUsername;
    }
    account.displayName = user.username ?? account.displayName;
    account.email = user.email ?? account.email;
    if (account.email.trim().isEmpty &&
        isMailboxLoginIdentity(account.username)) {
      account.email = account.username.trim();
    }
    account.quotaPerUnit = sub2QuotaPerUnit;
    account.quota = roundMoney(user.balance);
    account.usedQuota = roundMoney(usedQuota ?? account.usedQuota);
    account.requestCount = requestCount ?? account.requestCount;
    account.checkinEnabled = false;
    account.checkedInToday = false;
    account.updatedAt = isoNow();
    account.lastSyncedAt = account.updatedAt;
    account.lastError = null;
    if (user.status.isNotEmpty && user.status != 'active') {
      account.status = AccountStatus.disabled;
      return;
    }
    account.status = AccountStatus.active;
    appendTrendPoint(account);
    updateAccountStatus(account);
  }

  UsageLog mapSub2UsageLog(Account account, Sub2UsageLog log) {
    final time = createdAtToIso(log.createdAt) ?? log.createdAt ?? isoNow();
    return UsageLog(
      id: '${account.id}:usage:${log.id ?? time}',
      accountId: account.id,
      platformType: account.platformType,
      apiKeyId: log.apiKeyId != null ? '${account.id}:${log.apiKeyId}' : '',
      apiKeyName: log.apiKeyName?.isNotEmpty == true
          ? log.apiKeyName!
          : '未命名密钥',
      model: log.model?.isNotEmpty == true ? log.model! : '未知模型',
      time: time,
      quotaCost: roundMoney(log.actualCost ?? log.totalCost ?? 0),
      promptTokens: log.inputTokens ?? 0,
      completionTokens: log.outputTokens ?? 0,
      success: true,
      ip: log.ip ?? '',
      group: log.group ?? '',
      useTime: log.durationMs ?? 0,
      isStream: log.stream == true,
      type: 2,
    );
  }

  UsageLog mapNewApiUsageLog(Account account, NewApiUsageLog log) {
    final time = log.timeIso ?? unixToIso(log.createdAt) ?? isoNow();
    final type = log.type ?? 2;
    return UsageLog(
      id: '${account.id}:usage:${log.id ?? time}',
      accountId: account.id,
      platformType: account.platformType,
      apiKeyId: log.tokenId != null ? '${account.id}:${log.tokenId}' : '',
      apiKeyName: log.tokenName?.isNotEmpty == true ? log.tokenName! : '未命名密钥',
      model: log.modelName?.isNotEmpty == true ? log.modelName! : '未知模型',
      time: time,
      quotaCost: resolveUsageQuotaCost(
        type: type,
        quota: log.quota ?? 0,
        content: log.content ?? '',
        quotaPerUnit: account.quotaPerUnit,
      ),
      promptTokens: log.promptTokens ?? 0,
      completionTokens: log.completionTokens ?? 0,
      success: type != 5,
      ip: log.ip ?? '',
      group: log.group ?? '',
      content: log.content ?? '',
      useTime: log.useTime ?? 0,
      isStream: log.isStream == true,
      type: type,
      requestId: log.requestId ?? '',
      upstreamRequestId: log.upstreamRequestId ?? '',
      channelName: log.channelName ?? '',
      username: log.username ?? '',
      other: Map<String, dynamic>.from(log.other),
    );
  }

  void mergeSub2UsageLogs(Account account, List<Sub2UsageLog> logs) {
    _usageDirty = true;
    final mapped = logs.map((log) => mapSub2UsageLog(account, log)).toList();
    usageLogs = _keepLatestPerAccount(
      [...mapped, ...usageLogs.where((item) => item.accountId != account.id)]
        ..sort(
          (left, right) =>
              DateTime.parse(right.time).compareTo(DateTime.parse(left.time)),
        ),
      (item) => item.accountId,
    );
  }

  void mergeUsageLogs(Account account, List<NewApiUsageLog> logs) {
    _usageDirty = true;
    final mapped = logs.map((log) => mapNewApiUsageLog(account, log)).toList();
    usageLogs = _keepLatestPerAccount(
      [...mapped, ...usageLogs.where((item) => item.accountId != account.id)]
        ..sort(
          (left, right) =>
              DateTime.parse(right.time).compareTo(DateTime.parse(left.time)),
        ),
      (item) => item.accountId,
    );
  }

  void mergeCheckinLogs(Account account, List<NewApiCheckinRecord> records) {
    final mapped = records.map((record) {
      final time =
          DateTime.tryParse('${record.checkinDate}T09:00:00')
              ?.toUtc()
              .toIso8601String() ??
          isoNow();
      final reward = quotaToMoney(record.quotaAwarded, account.quotaPerUnit);
      return _checkinLogForAccount(
        account: account,
        id: '${account.id}:checkin:${record.checkinDate}',
        time: time,
        success: true,
        message: '签到成功，获得 ${reward.toStringAsFixed(2)} 额度',
        reward: reward,
      );
    }).toList();
    checkinLogs = _keepLatestPerAccount(
      [...mapped, ...checkinLogs.where((item) => item.accountId != account.id)]
        ..sort(
          (left, right) =>
              DateTime.parse(right.time).compareTo(DateTime.parse(left.time)),
        ),
      (item) => item.accountId,
    );
  }

  void replaceAccountKeys(String accountId, List<ApiKey> nextKeys) {
    apiKeys = [
      ...apiKeys.where((item) => item.accountId != accountId),
      ...nextKeys,
    ];
  }

  Future<AccountSession> refreshSub2Session(
    Account account,
    AccountSession session,
  ) async {
    if (session.refreshToken == null || session.refreshToken!.isEmpty) {
      throw ApiError(sessionExpiredMessage, 401);
    }
    final tokens = await refreshSub2Token(
      account.baseUrl,
      session.refreshToken!,
    );
    session.accessToken = tokens.accessToken;
    if (tokens.refreshToken != null && tokens.refreshToken!.isNotEmpty) {
      session.refreshToken = tokens.refreshToken;
    }
    await persist();
    return session;
  }

  void markSessionExpired(Account account) {
    account.status = AccountStatus.expired;
    account.lastError = sessionExpiredMessage;
    unawaited(persist());
    _bump();
  }

  void markNetworkBlocked(Account account, [Object? error]) {
    account.status = AccountStatus.blocked;
    if (error != null && isDnsPollutedError(error)) {
      account.lastError = kDnsPollutedMessage;
    } else if (error == null) {
      account.lastError = kSiteNetworkBlockedMessage;
    } else {
      account.lastError = userFacingError(error, kSiteNetworkBlockedMessage);
    }
    unawaited(persist());
    _bump();
  }

  Future<ApiError> _classifyReachabilityError(
    Account account,
    Object error,
  ) async {
    if (shouldDiagnoseSiteAccess(error) ||
        isNetworkBlockedError(error) ||
        isDnsPollutedError(error)) {
      final diagnosis = await diagnoseSiteAccess(account.baseUrl, error);
      if (diagnosis.issue == SiteAccessIssue.dnsPolluted) {
        markNetworkBlocked(account, ApiError(diagnosis.message));
        return ApiError(
          diagnosis.message,
          error is ApiError ? error.status : null,
        );
      }
      if (diagnosis.issue == SiteAccessIssue.networkBlocked) {
        markNetworkBlocked(account, ApiError(diagnosis.message));
        return ApiError(
          diagnosis.message,
          error is ApiError ? error.status : 403,
        );
      }
    }
    if (isDnsPollutedError(error) ||
        looksLikeCertificateMismatch(error) ||
        looksLikeHostLookupFailure(error)) {
      markNetworkBlocked(account, ApiError(kDnsPollutedMessage));
      return ApiError(
        kDnsPollutedMessage,
        error is ApiError ? error.status : null,
      );
    }
    if (isNetworkBlockedError(error) || looksLikeTransportFailure(error)) {
      final message =
          isNetworkBlockedError(error) && !looksLikeTransportFailure(error)
          ? userFacingError(error, kSiteNetworkBlockedMessage)
          : kSiteUnreachableMessage;
      markNetworkBlocked(account, ApiError(message));
      return ApiError(message, error is ApiError ? error.status : 403);
    }
    if (isAuthExpiredError(error)) {
      markSessionExpired(account);
      return ApiError(sessionExpiredMessage, 401);
    }
    return ApiError(
      userFacingError(error, '同步失败'),
      error is ApiError ? error.status : null,
    );
  }

  Future<T> withAccountAuth<T>(
    Account account,
    Future<T> Function(AccountSession session) run,
  ) async {
    final session = sessionByAccount(account.id);
    if (session == null) {
      markSessionExpired(account);
      throw ApiError(sessionExpiredMessage, 401);
    }
    final proxy = resolvedProxy(account.proxy);
    try {
      await runWithProxy(
        proxy,
        () => _prepareNewApiSession(account, session),
        cookies: session.cookies,
      );
    } catch (error) {
      if (shouldDiagnoseSiteAccess(error) ||
          isNetworkBlockedError(error) ||
          isDnsPollutedError(error)) {
        throw await _classifyReachabilityError(account, error);
      }
      if (isAuthExpiredError(error)) {
        throw await _classifyReachabilityError(account, error);
      }
      rethrow;
    }
    return runWithProxy(proxy, () async {
      try {
        return await run(session);
      } catch (error) {
        if (shouldDiagnoseSiteAccess(error) ||
            isNetworkBlockedError(error) ||
            isDnsPollutedError(error)) {
          throw await _classifyReachabilityError(account, error);
        }
        if (!isAuthExpiredError(error)) {
          rethrow;
        }
        if (account.platformType == PlatformType.sub2api &&
            session.refreshToken != null &&
            session.refreshToken!.isNotEmpty) {
          try {
            final nextSession = await refreshSub2Session(account, session);
            return await run(nextSession);
          } catch (refreshError) {
            throw await _classifyReachabilityError(account, refreshError);
          }
        }
        if (_usesNewApiPanelSession(account)) {
          try {
            await _prepareNewApiSession(account, session, force: true);
            return await runWithProxy(
              proxy,
              () => run(session),
              cookies: session.cookies,
            );
          } catch (refreshError) {
            throw await _classifyReachabilityError(account, refreshError);
          }
        }
        throw await _classifyReachabilityError(account, error);
      }
    }, cookies: session.cookies);
  }

  bool _usesNewApiPanelSession(Account account) {
    return account.platformType != PlatformType.sub2api &&
        account.authMode == AuthMode.password;
  }

  final Map<String, Future<void>> _newApiRefreshInFlight = {};

  Future<void> _prepareNewApiSession(
    Account account,
    AccountSession session, {
    bool force = false,
  }) async {
    if (!_usesNewApiPanelSession(account)) {
      return;
    }
    final pending = _newApiRefreshInFlight[account.id];
    if (pending != null) {
      await pending;
      if (!force && newApiAccessTokenIsFresh(session.accessToken)) {
        return;
      }
    }
    final future = _refreshNewApiSession(account, session, force: force);
    _newApiRefreshInFlight[account.id] = future;
    try {
      await future;
    } finally {
      if (identical(_newApiRefreshInFlight[account.id], future)) {
        _newApiRefreshInFlight.remove(account.id);
      }
    }
  }

  Future<void> _refreshNewApiSession(
    Account account,
    AccountSession session, {
    required bool force,
  }) async {
    final webCookies = await readSiteCookieHeader(account.baseUrl);
    final merged = mergeCookies([session.cookies, webCookies]);
    if (merged.isNotEmpty) {
      session.cookies = merged;
    }
    if (!force && newApiAccessTokenIsFresh(session.accessToken)) {
      return;
    }
    if (session.cookies.isEmpty) {
      return;
    }
    try {
      final refreshed = await refreshNewApiAccessToken(
        account.baseUrl,
        session.cookies,
      );
      if (refreshed == null) {
        if (!newApiAccessTokenIsFresh(session.accessToken) &&
            session.cookies.isNotEmpty) {
          session.accessToken = asCookieAuth(session.cookies);
          await persist();
        }
        return;
      }
      session.accessToken = refreshed.accessToken;
      session.cookies = refreshed.cookies;
      if (refreshed.userId.isNotEmpty) {
        session.userId = refreshed.userId;
      }
      await persist();
    } on ApiError catch (error) {
      if (error.status == 404 || error.status == 405) {
        if (session.cookies.isNotEmpty) {
          session.accessToken = asCookieAuth(session.cookies);
          await persist();
        }
        return;
      }
      rethrow;
    }
  }

  Future<List<TokenGroupOption>> loadTokenGroups(
    String accountId, {
    bool force = false,
  }) async {
    final account = accountById(accountId);
    if (account == null) {
      return [];
    }
    if (!force && tokenGroups.containsKey(accountId)) {
      return tokenGroups[accountId]!;
    }
    try {
      final groups = await withAccountAuth(account, (session) async {
        if (account.platformType == PlatformType.sub2api) {
          return fetchSub2Groups(account.baseUrl, session.accessToken);
        }
        return fetchUserGroups(
          account.baseUrl,
          session.accessToken,
          session.userId,
        );
      });
      if (groups.isNotEmpty) {
        tokenGroups[accountId] = groups;
        await _persistTokenGroupCache();
      }
    } catch (error) {
      if (isAuthExpiredError(error)) {
        rethrow;
      }
      return tokenGroups[accountId] ?? fallbackGroups(account);
    }
    _bump();
    return tokenGroups[accountId] ?? fallbackGroups(account);
  }

  Future<List<String>> loadGroupModels(
    String accountId,
    String group, {
    bool force = false,
  }) async {
    final account = accountById(accountId);
    final cacheKey = '$accountId:${group.isEmpty ? 'all' : group}';
    if (account == null) {
      return [];
    }
    if (account.platformType == PlatformType.sub2api) {
      tokenModels[cacheKey] = [];
      return [];
    }
    if (!force && tokenModels.containsKey(cacheKey)) {
      return tokenModels[cacheKey]!;
    }
    try {
      final models = await withAccountAuth(
        account,
        (session) => fetchGroupModels(
          account.baseUrl,
          session.accessToken,
          session.userId,
          group,
        ),
      );
      tokenModels[cacheKey] = models;
      await _persistTokenModelCache();
    } catch (error) {
      if (isAuthExpiredError(error)) {
        rethrow;
      }
      return tokenModels[cacheKey] ?? [];
    }
    _bump();
    return tokenModels[cacheKey] ?? [];
  }

  Future<Account> syncSub2Account(Account account) =>
      withAccountAuth(account, (activeSession) async {
        final user = await fetchCurrentSub2User(
          account.baseUrl,
          activeSession.accessToken,
        );
        activeSession.userId = '${user.id}';
        final tokens = await fetchSub2Keys(
          account.baseUrl,
          activeSession.accessToken,
        );
        final stats = await fetchSub2DashboardStats(
          account.baseUrl,
          activeSession.accessToken,
        );
        applySub2UserSnapshot(
          account,
          user,
          usedQuota: stats?.totalActualCost,
          requestCount: stats?.totalRequests,
        );
        replaceAccountKeys(
          account.id,
          tokens.map((token) => mapSub2Key(account, token)).toList(),
        );
        await persist();
        _bump();
        return account;
      });

  Future<Account> syncAccount(String accountId) async {
    final account = accountById(accountId);
    if (account == null) {
      throw ApiError('账号不存在');
    }
    try {
      if (account.platformType == PlatformType.sub2api) {
        return await syncSub2Account(account);
      }
      return await withAccountAuth(account, (session) async {
        final user = await fetchCurrentUser(
          account.baseUrl,
          session.accessToken,
          session.userId,
        );
        session.userId = '${user.id}';
        applyUserSnapshot(account, user);
        final tokens = await fetchTokens(
          account.baseUrl,
          session.accessToken,
          session.userId,
        );
        final checkin = await fetchCheckinStatus(
          account.baseUrl,
          session.accessToken,
          session.userId,
        );
        replaceAccountKeys(
          account.id,
          tokens.map((token) => mapToken(account, token)).toList(),
        );
        if (checkin != null) {
          account.checkinEnabled = checkin.enabled;
        }
        if (!account.checkinEnabled) {
          account.checkedInToday = false;
        } else {
          account.checkedInToday =
              checkin?.checkedInToday ?? account.checkedInToday;
        }
        final records = checkin?.records ?? [];
        if (records.isNotEmpty) {
          final latest = records.first;
          account.lastCheckin =
              DateTime.tryParse('${latest.checkinDate}T09:00:00')
                  ?.toUtc()
                  .toIso8601String() ??
              account.lastCheckin;
          mergeCheckinLogs(account, records);
        }
        await persist();
        _bump();
        return account;
      });
    } catch (error) {
      if (account.status != AccountStatus.expired &&
          account.status != AccountStatus.blocked) {
        if (shouldDiagnoseSiteAccess(error) ||
            isNetworkBlockedError(error) ||
            isDnsPollutedError(error) ||
            looksLikeTransportFailure(error)) {
          throw await _classifyReachabilityError(account, error);
        }
        account.lastError = userFacingError(error, '同步失败');
        if (account.userId.isEmpty) {
          account.status = AccountStatus.pending;
        }
        await persist();
        _bump();
      }
      rethrow;
    }
  }

  Future<UsageLogQueryResult> queryUsageLogs(UsageLogQuery query) async {
    if (query.accountId.isEmpty) {
      return _queryAllAccountsUsageLogs(query);
    }
    final account = accountById(query.accountId);
    if (account == null) {
      throw ApiError('账号不存在');
    }
    final window = dateWindowFor(query.range);
    return withAccountAuth(account, (session) async {
      if (account.platformType == PlatformType.sub2api) {
        return _querySub2UsageLogs(account, session, query, window);
      }
      return _queryNewApiUsageLogs(account, session, query, window);
    });
  }

  Future<UsageLogQueryResult> _queryAllAccountsUsageLogs(
    UsageLogQuery query,
  ) async {
    if (accounts.isEmpty) {
      return UsageLogQueryResult(page: query.page, pageSize: query.pageSize);
    }
    Object? firstError;
    final results = <UsageLogQueryResult>[];
    await Future.wait(
      accounts.map((account) async {
        if (account.platformType == PlatformType.sub2api &&
            query.type != 0 &&
            query.type != 2) {
          return;
        }
        final need = query.page * query.pageSize;
        final fetchTop = need <= 100;
        try {
          results.add(
            await queryUsageLogs(
              UsageLogQuery(
                accountId: account.id,
                page: fetchTop ? 1 : query.page,
                pageSize: fetchTop
                    ? need.clamp(query.pageSize, 100)
                    : query.pageSize,
                type: account.platformType == PlatformType.sub2api
                    ? 2
                    : query.type,
                range: query.range,
                tokenName: query.tokenName,
                modelName: query.modelName,
                group: query.group,
              ),
            ),
          );
        } catch (error) {
          firstError ??= error;
        }
      }),
    );
    if (results.isEmpty) {
      final error = firstError;
      if (error != null) {
        throw error;
      }
      return UsageLogQueryResult(page: query.page, pageSize: query.pageSize);
    }
    final items = results.expand((result) => result.items).toList()
      ..sort((left, right) {
        final rightTime =
            DateTime.tryParse(right.time)?.millisecondsSinceEpoch ?? 0;
        final leftTime =
            DateTime.tryParse(left.time)?.millisecondsSinceEpoch ?? 0;
        return rightTime.compareTo(leftTime);
      });
    final offset = (query.page - 1) * query.pageSize;
    final pageItems = (query.page * query.pageSize) <= 100
        ? items.skip(offset).take(query.pageSize).toList()
        : items.take(query.pageSize).toList();
    return UsageLogQueryResult(
      items: pageItems,
      total: results.fold<int>(0, (sum, result) => sum + result.total),
      page: query.page,
      pageSize: query.pageSize,
      quotaTotal: roundMoney(
        results.fold<double>(0, (sum, result) => sum + result.quotaTotal),
      ),
      rpm: results.fold<int>(0, (sum, result) => sum + result.rpm),
      tpm: results.fold<int>(0, (sum, result) => sum + result.tpm),
      statsAvailable: results.any((result) => result.statsAvailable),
      totalKnown: results.every((result) => result.totalKnown),
    );
  }

  Future<UsageLogQueryResult> _queryNewApiUsageLogs(
    Account account,
    AccountSession session,
    UsageLogQuery query,
    DateWindow window,
  ) async {
    final page = await fetchUsageLogsPage(
      account.baseUrl,
      session.accessToken,
      session.userId,
      page: query.page,
      pageSize: query.pageSize,
      type: query.type,
      startTimestamp: window.startUnix,
      endTimestamp: window.endUnix,
      tokenName: query.tokenName.trim(),
      modelName: query.modelName.trim(),
      group: query.group.trim(),
    );
    final stat = await fetchUsageLogStat(
      account.baseUrl,
      session.accessToken,
      session.userId,
      type: query.type,
      startTimestamp: window.startUnix,
      endTimestamp: window.endUnix,
      tokenName: query.tokenName.trim(),
      modelName: query.modelName.trim(),
      group: query.group.trim(),
    );
    final items = page.items
        .map((log) => mapNewApiUsageLog(account, log))
        .toList();
    final pageQuota = roundMoney(
      items.fold<double>(0, (sum, log) => sum + log.quotaCost),
    );
    final useConsumeStat = query.type == 0 || query.type == 2;
    return UsageLogQueryResult(
      items: items,
      total: page.total,
      page: page.page,
      pageSize: page.pageSize,
      quotaTotal: useConsumeStat && stat != null
          ? quotaToMoney(stat.quota, account.quotaPerUnit)
          : pageQuota,
      rpm: useConsumeStat ? (stat?.rpm ?? 0) : 0,
      tpm: useConsumeStat ? (stat?.tpm ?? 0) : 0,
      statsAvailable: useConsumeStat && stat != null,
      totalKnown: page.totalKnown,
    );
  }

  Future<UsageLogQueryResult> _querySub2UsageLogs(
    Account account,
    AccountSession session,
    UsageLogQuery query,
    DateWindow window,
  ) async {
    final page = await fetchSub2UsageLogsPage(
      account.baseUrl,
      session.accessToken,
      page: query.page,
      pageSize: query.pageSize,
      startDate: window.startDate,
      endDate: window.endDate,
      model: query.modelName.trim(),
    );
    final stat = await fetchSub2UsageStats(
      account.baseUrl,
      session.accessToken,
      startDate: window.startDate,
      endDate: window.endDate,
      model: query.modelName.trim(),
    );
    final items = page.items
        .map((log) => mapSub2UsageLog(account, log))
        .toList();
    final pageQuota = roundMoney(
      items.fold<double>(0, (sum, log) => sum + log.quotaCost),
    );
    return UsageLogQueryResult(
      items: items,
      total: page.total,
      page: page.page,
      pageSize: page.pageSize,
      quotaTotal: roundMoney(stat?.totalActualCost ?? pageQuota),
      rpm: stat?.rpm ?? 0,
      tpm: stat?.tpm ?? 0,
      statsAvailable: stat != null,
      totalKnown: page.totalKnown,
    );
  }

  Future<void> hydrate() async {
    if (hydrated) {
      return;
    }
    await VaultStorage.init();
    final liveAccounts = VaultStorage.loadAccounts()
        .where((account) => account.baseUrl.trim().isNotEmpty)
        .toList();
    final liveIds = liveAccounts.map((account) => account.id).toSet();
    accounts = liveAccounts;
    sessions = (await VaultStorage.loadSessions())
        .where(
          (session) =>
              liveIds.contains(session.accountId) &&
              session.accessToken.isNotEmpty,
        )
        .toList();
    apiKeys = (await VaultStorage.loadApiKeys())
        .where((apiKey) => liveIds.contains(apiKey.accountId))
        .toList();
    checkinLogs = VaultStorage.loadCheckinLogs()
        .where((log) => liveIds.contains(log.accountId))
        .toList();
    usageLogs = VaultStorage.loadUsageLogs()
        .where((log) => liveIds.contains(log.accountId))
        .toList();
    final loadedRevealed = await VaultStorage.loadRevealedKeys();
    revealedKeys = Map.fromEntries(
      loadedRevealed.entries.where(
        (entry) => apiKeys.any((apiKey) => apiKey.id == entry.key),
      ),
    );
    final loadedPasswords = await VaultStorage.loadAccountPasswords();
    accountPasswords = Map.fromEntries(
      loadedPasswords.entries.where(
        (entry) => liveIds.contains(entry.key) && entry.value.isNotEmpty,
      ),
    );
    settings = VaultStorage.loadSettings();
    final loadedPricing = VaultStorage.loadPricingCatalogs();
    loadedPricing.removeWhere((accountId, _) => !liveIds.contains(accountId));
    pricingCatalogs
      ..clear()
      ..addAll(loadedPricing);
    final loadedGroups = VaultStorage.loadTokenGroupCache();
    loadedGroups.removeWhere((accountId, _) => !liveIds.contains(accountId));
    tokenGroups
      ..clear()
      ..addAll(loadedGroups);
    final loadedModels = VaultStorage.loadTokenModelCache();
    loadedModels.removeWhere((key, _) {
      final accountId = key.contains(':') ? key.split(':').first : key;
      return !liveIds.contains(accountId);
    });
    tokenModels
      ..clear()
      ..addAll(loadedModels);
    final hadPlaintextProxy =
        settings.networkProxy.password.isNotEmpty ||
        liveAccounts.any((account) => account.proxy.password.isNotEmpty);
    _applyProxySecrets(await VaultStorage.loadProxySecrets());
    HttpRequestLogger.instance.setEnabled(settings.developerLogEnabled);
    for (final account in accounts) {
      if (account.platformType == PlatformType.sub2api) {
        account.checkinEnabled = false;
        account.checkedInToday = false;
      }
      if (account.status == AccountStatus.disabled ||
          account.status == AccountStatus.pending) {
        continue;
      }
      final lastError = account.lastError ?? '';
      if (looksLikeDnsPollutedMessage(lastError) ||
          looksLikeNetworkBlockMessage(lastError) ||
          lastError.contains('连接超时') ||
          lastError.contains('连不上这个站点') ||
          lastError.contains('网络连接失败')) {
        account.status = AccountStatus.blocked;
        if (!looksLikeDnsPollutedMessage(lastError) &&
            (lastError.contains('连接超时') ||
                lastError.contains('连不上这个站点') ||
                lastError.contains('网络连接失败'))) {
          account.lastError = kSiteUnreachableMessage;
        }
        continue;
      }
      if (account.lastError == sessionExpiredMessage) {
        account.status = AccountStatus.expired;
        continue;
      }
      if (account.status == AccountStatus.blocked ||
          account.status == AccountStatus.expired) {
        continue;
      }
      updateAccountStatus(account);
    }
    final loadedLogins = await VaultStorage.loadIdentityLogins();
    identityLogins = [
      for (final account in loadedLogins.accounts)
        if (isOAuthIdentityProvider(account.provider)) account,
    ];
    identityLoginSelectedIds = {
      for (final entry in loadedLogins.selectedIds.entries)
        if (isOAuthIdentityProvider(entry.key)) entry.key: entry.value,
    };
    identitySessions = await VaultStorage.loadIdentitySessions();
    identitySessions.removeWhere(
      (id, snapshot) => !isOAuthIdentityProvider(snapshot.provider),
    );
    googleIdentity = await VaultStorage.loadGoogleIdentity();
    githubIdentity = await VaultStorage.loadGitHubIdentity();
    await VaultStorage.clearQqMailIdentity();
    _migrateLegacyIdentitySession(googleIdentityProvider, googleIdentity);
    _migrateLegacyIdentitySession(githubIdentityProvider, githubIdentity);
    _refreshProviderIdentityFields();
    await restoreConnectedIdentityCookies([googleIdentity, githubIdentity]);
    hydrated = true;
    if (hadPlaintextProxy) {
      await persist();
    }
    _bump();
  }

  Future<bool>? _refreshInFlight;

  Future<bool> refreshAllAccounts() {
    return _refreshInFlight ??=
        () async {
          isRefreshing = true;
          _bump();
          try {
            await _withDeferredPersist(() async {
              await Future.wait(
                accounts
                    .where((account) {
                      if (account.status == AccountStatus.disabled ||
                          account.status == AccountStatus.pending) {
                        return false;
                      }
                      return sessionByAccount(account.id) != null;
                    })
                    .map(
                      (account) =>
                          syncAccount(account.id).catchError((_) => account),
                    ),
              );
            });
            return true;
          } finally {
            isRefreshing = false;
            _refreshInFlight = null;
            _bump();
          }
        }().then((ok) {
          if (ok) {
            notifyQuotaAlerts();
          }
          return ok;
        });
  }

  Future<CheckinLog?> checkinAccount(String accountId) async {
    final account = accountById(accountId);
    if (account == null) {
      return null;
    }
    if (account.status == AccountStatus.disabled ||
        account.status == AccountStatus.pending ||
        account.status == AccountStatus.expired ||
        account.status == AccountStatus.blocked) {
      return _checkinLogForAccount(
        account: account,
        id: makeId('checkin-skip'),
        time: isoNow(),
        success: false,
        message: account.status == AccountStatus.disabled
            ? '账号已停用，无法签到'
            : account.status == AccountStatus.expired
            ? sessionExpiredMessage
            : account.status == AccountStatus.blocked
            ? (account.dnsPolluted
                  ? kDnsPollutedMessage
                  : kSiteNetworkBlockedMessage)
            : '账号待连接，暂不能签到',
      );
    }
    if (!account.checkinEnabled) {
      return null;
    }
    if (account.checkedInToday) {
      return _checkinLogForAccount(
        account: account,
        id: makeId('checkin-repeat'),
        time: isoNow(),
        success: false,
        message: '今日已完成签到',
      );
    }
    try {
      final result = await withAccountAuth(
        account,
        (session) => _doCheckinWithTurnstile(account, session),
      );
      final reward = quotaToMoney(result.quotaAwarded, account.quotaPerUnit);
      final log = _checkinLogForAccount(
        account: account,
        id: makeId('checkin'),
        time: isoNow(),
        success: true,
        message: reward > 0
            ? '签到成功，获得 \$${reward.toStringAsFixed(2)} 额度'
            : result.message,
        reward: reward,
      );
      checkinLogs = _keepLatestPerAccount(
        [log, ...checkinLogs]..sort(
          (left, right) =>
              DateTime.parse(right.time).compareTo(DateTime.parse(left.time)),
        ),
        (item) => item.accountId,
      );
      await syncAccount(account.id);
      return log;
    } catch (error) {
      return _checkinLogForAccount(
        account: account,
        id: makeId('checkin-error'),
        time: isoNow(),
        success: false,
        message: userFacingError(error, '签到失败'),
      );
    }
  }

  Future<({double quotaAwarded, String message})> _doCheckinWithTurnstile(
    Account account,
    AccountSession session,
  ) async {
    var token = '';
    try {
      token = (await solveNewApiTurnstileForSite(account.baseUrl)) ?? '';
    } on ApiError catch (error) {
      if (error.message.contains('验证码服务')) {
        rethrow;
      }
    } catch (_) {}

    Future<({double quotaAwarded, String message})> submit(String value) {
      return doCheckin(
        account.baseUrl,
        session.accessToken,
        session.userId,
        turnstileToken: value,
      );
    }

    try {
      return await submit(token);
    } catch (error) {
      if (!looksLikeTurnstileRequired(error)) {
        rethrow;
      }
      final retry =
          (await solveNewApiTurnstileForSite(
            account.baseUrl,
            ignoreDisabled: true,
          )) ??
          '';
      if (retry.isEmpty) {
        throw ApiError('该站点签到需要过人机验证。请到「我的 → 验证码服务」开启并填好 ClientKey');
      }
      try {
        return await submit(retry);
      } catch (retryError) {
        if (looksLikeTurnstileRequired(retryError)) {
          throw ApiError('人机验证未通过，签到失败。请到「我的 → 验证码服务」确认 Key 和余额后重试');
        }
        rethrow;
      }
    }
  }

  Future<List<CheckinLog>> checkinAll() async {
    final targets = accounts.where(isCheckinEligible).toList();
    final results = await Future.wait(
      targets.map((account) => checkinAccount(account.id)),
    );
    return results.whereType<CheckinLog>().toList();
  }

  Future<List<CheckinLog>> autoCheckinAccounts() async {
    final due = accounts
        .where(
          (account) => isCheckinEligible(account) && !account.checkedInToday,
        )
        .toList();
    if (due.isEmpty) {
      return [];
    }
    final results = await Future.wait(
      due.map((account) => checkinAccount(account.id)),
    );
    return results.whereType<CheckinLog>().toList();
  }

  CheckinSummary summarizeCheckin(List<CheckinLog> results) {
    if (results.isEmpty) {
      return const CheckinSummary(
        message: '当前没有可签到的账号',
        type: FeedbackType.text,
      );
    }
    final successes = results.where((result) => result.success).toList();
    if (successes.isNotEmpty) {
      return CheckinSummary(
        message: '完成 ${successes.length} 个账号签到',
        type: FeedbackType.success,
      );
    }
    if (results.every((result) => result.message.contains('今日已完成签到'))) {
      return const CheckinSummary(
        message: '今天该签的都已经签过了',
        type: FeedbackType.text,
      );
    }
    final firstError = results
        .where((result) => !result.success)
        .firstOrNull
        ?.message;
    return CheckinSummary(
      message: firstError ?? '签到未完成',
      type: FeedbackType.warning,
    );
  }

  AccountDraft toAccountDraft([Account? account]) {
    if (account == null) {
      return AccountDraft();
    }
    return AccountDraft(
      id: account.id,
      alias: account.alias,
      siteName: account.siteName,
      baseUrl: account.baseUrl,
      platformType: account.platformType,
      authMode: account.authMode,
      username: account.username,
      password: passwordForAccount(account.id),
      accessToken: visibleLoginAccessToken(
        sessionByAccount(account.id)?.accessToken ?? '',
      ),
      userId: account.userId,
      tags: [...account.tags],
      topupRatio: account.topupRatio,
      apiUrls: [...account.apiUrls],
      proxy: account.proxy.copy(),
      excludeFromTotalQuota: account.excludeFromTotalQuota,
    );
  }

  Future<Account> saveAccount(AccountDraft draft) async {
    final now = isoNow();
    final existing = draft.id == null ? null : accountById(draft.id!);
    final baseUrl = normalizeBaseUrl(draft.baseUrl);
    final existingToken = existing == null
        ? ''
        : (sessionByAccount(existing.id)?.accessToken ?? '').trim();
    final submittedToken = draft.accessToken.trim();
    final hasNewAccessToken =
        submittedToken.isNotEmpty && submittedToken != existingToken;
    final hasFreshCredentials =
        hasNewAccessToken ||
        (draft.platformType == PlatformType.sub2api
            ? (draft.username.trim().isNotEmpty && draft.password.isNotEmpty)
            : draft.authMode == AuthMode.accessToken
            ? false
            : draft.username.trim().isNotEmpty && draft.password.isNotEmpty);
    if (existing == null && !hasFreshCredentials) {
      throw ApiError(
        draft.platformType == PlatformType.sub2api ||
                draft.authMode == AuthMode.password
            ? '请填写用户名和密码后自动登录'
            : '请填写访问令牌',
      );
    }
    if (draft.proxy.mode == NetworkProxyMode.custom &&
        !draft.proxy.isConfigured) {
      throw ApiError('请填写主机地址和端口');
    }
    return runWithProxy(
      resolvedProxy(draft.proxy),
      () => _saveAccount(draft, now, existing, baseUrl, hasFreshCredentials),
      cookies: draft.cookies,
    );
  }

  Future<Account> _saveAccount(
    AccountDraft draft,
    String now,
    Account? existing,
    String baseUrl,
    bool hasFreshCredentials,
  ) async {
    if (existing != null &&
        existing.baseUrl != baseUrl &&
        !hasFreshCredentials) {
      throw ApiError('站点地址已更改，请重新登录');
    }

    ConnectResult? connected = existing == null
        ? null
        : ConnectResult(
            baseUrl: baseUrl,
            accessToken: sessionByAccount(existing.id)?.accessToken ?? '',
            refreshToken: sessionByAccount(existing.id)?.refreshToken ?? '',
            user: NewApiUser(
              id: int.tryParse(existing.userId) ?? 0,
              username: existing.username,
              displayName: existing.displayName,
              email: existing.email,
              group: existing.group,
              requestCount: existing.requestCount,
            ),
            quotaPerUnit: existing.quotaPerUnit,
            checkinEnabled: existing.checkinEnabled,
            systemName: existing.siteName,
          );

    if (hasFreshCredentials || (connected?.accessToken.isEmpty ?? true)) {
      if (draft.platformType == PlatformType.sub2api) {
        var turnstileToken = draft.turnstileToken;
        if ((turnstileToken == null || turnstileToken.trim().isEmpty) &&
            draft.accessToken.trim().isEmpty) {
          turnstileToken = await solveTurnstileForSite(baseUrl);
        }
        final sub2 = await connectSub2Account(
          baseUrl: baseUrl,
          email: draft.username,
          password: draft.password,
          turnstileToken: turnstileToken,
          accessToken: draft.accessToken,
          refreshToken: draft.refreshToken,
        );
        connected = ConnectResult(
          baseUrl: sub2.baseUrl,
          accessToken: sub2.accessToken,
          refreshToken: sub2.refreshToken,
          user: NewApiUser(
            id: sub2.user.id,
            username: sub2.user.username,
            displayName: sub2.user.username,
            email: sub2.user.email,
            group: 'default',
            quota: sub2.user.balance,
            status: sub2.user.status == 'disabled' ? 0 : 1,
          ),
          quotaPerUnit: sub2QuotaPerUnit,
          checkinEnabled: false,
          systemName: sub2.settings.siteName ?? '',
        );
      } else {
        var loginTurnstileToken = '';
        if (draft.accessToken.trim().isEmpty &&
            draft.authMode == AuthMode.password) {
          loginTurnstileToken =
              (await solveNewApiTurnstileForSite(baseUrl)) ?? '';
        }
        connected = await connectAccount(
          baseUrl: baseUrl,
          username: draft.username,
          password: draft.password,
          accessToken: draft.accessToken.trim().isNotEmpty
              ? draft.accessToken
              : null,
          userId: draft.userId.isNotEmpty ? draft.userId : existing?.userId,
          turnstileToken: loginTurnstileToken,
        );
      }
    }

    final ready = connected!;
    final cookies = mergeCookies([draft.cookies, ready.cookies]);
    var accessToken = ready.accessToken;
    if (draft.issueLoginAccessToken &&
        draft.platformType != PlatformType.sub2api) {
      accessToken = await ensureIssuedAccessToken(
        baseUrl: ready.baseUrl,
        accessToken: accessToken,
        cookies: cookies,
        userId: '${ready.user.id}',
      );
      if (newApiAccessTokenIsFresh(accessToken)) {
        draft.authMode = AuthMode.accessToken;
      }
    }
    final siteName = draft.siteName.trim().isNotEmpty
        ? draft.siteName.trim()
        : (ready.systemName.trim().isNotEmpty
              ? ready.systemName.trim()
              : hostnameOf(ready.baseUrl));
    final loginUsername = preferMailboxLoginIdentity(
      draft.username,
      ready.user.username,
    );
    final alias = draft.alias.trim().isNotEmpty
        ? draft.alias.trim()
        : (isMailboxLoginIdentity(loginUsername)
              ? mailboxLocalPart(loginUsername)
              : (ready.user.displayName?.isNotEmpty == true
                    ? ready.user.displayName!
                    : (ready.user.username ?? siteName)));

    if (existing != null) {
      existing.alias = alias;
      existing.siteName = siteName;
      existing.baseUrl = ready.baseUrl;
      existing.platformType = draft.platformType;
      existing.authMode = draft.authMode;
      existing.tags = [...draft.tags];
      existing.proxy = draft.proxy.copy();
      existing.topupRatio = sanitizeTopupRatio(draft.topupRatio);
      existing.apiUrls = [...draft.apiUrls];
      existing.excludeFromTotalQuota = draft.excludeFromTotalQuota;
      existing.quotaPerUnit = ready.quotaPerUnit;
      existing.checkinEnabled = ready.checkinEnabled;
      existing.updatedAt = now;
      final session = sessionByAccount(existing.id);
      if (session != null) {
        session.accessToken = accessToken;
        session.userId = '${ready.user.id}';
        if (ready.refreshToken.isNotEmpty) {
          session.refreshToken = ready.refreshToken;
        }
        final nextCookies = mergeCookies([session.cookies, cookies]);
        if (nextCookies.isNotEmpty) {
          session.cookies = nextCookies;
        }
      } else {
        sessions.add(
          AccountSession(
            accountId: existing.id,
            accessToken: accessToken,
            userId: '${ready.user.id}',
            refreshToken: ready.refreshToken.isEmpty
                ? null
                : ready.refreshToken,
            cookies: cookies,
          ),
        );
      }
      if (hasFreshCredentials) {
        applyUserSnapshot(existing, ready.user);
      }
      if (isMailboxLoginIdentity(loginUsername)) {
        existing.username = loginUsername;
        if (existing.email.trim().isEmpty) {
          existing.email = loginUsername;
        }
      }
      _rememberPassword(existing.id, draft.password);
      await persist();
      await syncAccount(existing.id);
      await persist();
      _bump();
      return existing;
    }

    final account = Account(
      id: makeId('account'),
      alias: alias,
      siteName: siteName,
      baseUrl: ready.baseUrl,
      platformType: draft.platformType,
      authMode: draft.authMode,
      userId: '${ready.user.id}',
      username: loginUsername,
      displayName: ready.user.displayName ?? '',
      email: (ready.user.email ?? '').trim().isNotEmpty
          ? ready.user.email!.trim()
          : (isMailboxLoginIdentity(loginUsername) ? loginUsername : ''),
      group: ready.user.group ?? 'default',
      quota: quotaToMoney(ready.user.quota, ready.quotaPerUnit),
      usedQuota: quotaToMoney(ready.user.usedQuota, ready.quotaPerUnit),
      requestCount: ready.user.requestCount,
      quotaPerUnit: ready.quotaPerUnit,
      status: AccountStatus.active,
      checkedInToday: false,
      checkinEnabled: ready.checkinEnabled,
      tags: [...draft.tags],
      proxy: draft.proxy.copy(),
      topupRatio: sanitizeTopupRatio(draft.topupRatio),
      apiUrls: [...draft.apiUrls],
      excludeFromTotalQuota: draft.excludeFromTotalQuota,
      trend: [],
      lastSyncedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    applyUserSnapshot(account, ready.user);
    if (isMailboxLoginIdentity(loginUsername)) {
      account.username = loginUsername;
      if (account.email.trim().isEmpty) {
        account.email = loginUsername;
      }
    }
    accounts = [account, ...accounts];
    _rememberPassword(account.id, draft.password);
    sessions.add(
      AccountSession(
        accountId: account.id,
        accessToken: accessToken,
        userId: '${ready.user.id}',
        refreshToken: ready.refreshToken.isEmpty ? null : ready.refreshToken,
        cookies: cookies,
      ),
    );
    await persist();
    await syncAccount(account.id);
    await persist();
    _bump();
    return account;
  }

  Future<String> reloginAccount(
    String accountId, {
    required Future<({String accessToken, String refreshToken, String cookies})>
    Function()
    capture,
  }) async {
    final account = accountById(accountId);
    if (account == null) {
      throw ApiError('账号不存在');
    }
    final captured = await capture();
    if (captured.accessToken.trim().isEmpty) {
      return 'need-form';
    }
    final session = sessionByAccount(account.id);
    if (session != null) {
      session.accessToken = captured.accessToken;
      if (captured.refreshToken.isNotEmpty) {
        session.refreshToken = captured.refreshToken;
      }
      if (captured.cookies.isNotEmpty) {
        session.cookies = mergeCookies([session.cookies, captured.cookies]);
      }
    } else {
      sessions.add(
        AccountSession(
          accountId: account.id,
          accessToken: captured.accessToken,
          userId: account.userId,
          refreshToken: captured.refreshToken.isEmpty
              ? null
              : captured.refreshToken,
          cookies: captured.cookies,
        ),
      );
    }
    await persist();
    await syncAccount(account.id);
    return 'synced';
  }

  Future<void> deleteAccount(String accountId) async {
    final account = accountById(accountId);
    accounts = accounts.where((item) => item.id != accountId).toList();
    sessions = sessions
        .where((session) => session.accountId != accountId)
        .toList();
    apiKeys = apiKeys.where((apiKey) => apiKey.accountId != accountId).toList();
    checkinLogs = checkinLogs
        .where((log) => log.accountId != accountId)
        .toList();
    usageLogs = usageLogs.where((log) => log.accountId != accountId).toList();
    _usageDirty = true;
    revealedKeys.removeWhere((key, _) => key.startsWith('$accountId:'));
    accountPasswords.remove(accountId);
    pricingCatalogs.remove(accountId);
    tokenGroups.remove(accountId);
    tokenModels.removeWhere((key, _) => key.startsWith('$accountId:'));
    await persist();
    await _persistPricingCatalogs();
    await _persistTokenGroupCache();
    await _persistTokenModelCache();
    if (account != null) {
      try {
        await clearSiteWebViewState(
          account.baseUrl,
          extraUrls: account.apiUrls,
        );
      } catch (_) {}
    }
    _bump();
  }

  ApiKeyDraft toApiKeyDraft({ApiKey? apiKey, String accountId = ''}) {
    if (apiKey == null) {
      final account = accountById(accountId);
      return ApiKeyDraft(
        accountId: accountId,
        group: account?.group ?? 'default',
      );
    }
    return ApiKeyDraft(
      id: apiKey.id,
      accountId: apiKey.accountId,
      name: apiKey.name,
      unlimitedQuota: apiKey.unlimitedQuota,
      remainQuota: apiKey.unlimitedQuota ? '' : '${apiKey.remainQuota}',
      expiresAt: apiKey.expiresAt == null
          ? ''
          : apiKey.expiresAt!.substring(0, 10),
      group: apiKey.group,
      modelLimitsText: apiKey.modelLimits.join(', '),
      allowIpsText: apiKey.allowIps.join(', '),
      crossGroupRetry: apiKey.crossGroupRetry,
    );
  }

  Map<String, dynamic> tokenPayload(
    Account account,
    ApiKeyDraft draft, [
    int? remoteId,
  ]) {
    final models = splitList(draft.modelLimitsText);
    final remainQuota = draft.unlimitedQuota
        ? 0
        : ((num.tryParse(draft.remainQuota) ?? 0) * account.quotaPerUnit)
              .round();
    return {
      'id': remoteId,
      'name': draft.name.trim(),
      'unlimited_quota': draft.unlimitedQuota,
      'remain_quota': remainQuota < 0 ? 0 : remainQuota,
      'expired_time': dateInputToUnix(draft.expiresAt),
      'group': draft.group.isEmpty
          ? defaultGroupForAccount(account)
          : draft.group,
      'model_limits_enabled': models.isNotEmpty,
      'model_limits': models.join(','),
      'allow_ips': splitList(draft.allowIpsText).join('\n'),
      'cross_group_retry':
          (draft.group.isEmpty
                  ? defaultGroupForAccount(account)
                  : draft.group) ==
              'auto' &&
          draft.crossGroupRetry,
    };
  }

  Future<ApiKey?> saveApiKey(ApiKeyDraft draft) async {
    final account = accountById(draft.accountId);
    if (account == null) {
      return null;
    }
    final existing = draft.id == null ? null : apiKeyById(draft.id!);
    await withAccountAuth(account, (session) async {
      if (account.platformType == PlatformType.sub2api) {
        var groups = await loadTokenGroups(account.id);
        var selectedGroup = groups
            .where((group) => group.name == draft.group)
            .firstOrNull;
        if (selectedGroup?.remoteId == null) {
          groups = await loadTokenGroups(account.id, force: true);
          selectedGroup = groups
              .where((group) => group.name == draft.group)
              .firstOrNull;
        }
        final remainQuota = draft.unlimitedQuota
            ? 0
            : num.tryParse(draft.remainQuota) ?? 0;
        final expiresAt = draft.expiresAt.trim();
        int? expiresInDays;
        if (expiresAt.isNotEmpty) {
          final target = DateTime.tryParse('${expiresAt}T23:59:59');
          if (target != null) {
            expiresInDays =
                ((target.difference(DateTime.now()).inMilliseconds) / 86400000)
                    .ceil()
                    .clamp(1, 3650);
          }
        }
        final payload = <String, dynamic>{
          'name': draft.name.trim(),
          'group_id': selectedGroup?.remoteId,
          'quota': remainQuota < 0 ? 0 : remainQuota,
          'ip_whitelist': splitList(draft.allowIpsText),
          'expires_in_days': ?expiresInDays,
        };
        if (existing != null) {
          await updateSub2Key(
            account.baseUrl,
            session.accessToken,
            existing.remoteId,
            payload,
          );
        } else {
          await createSub2Key(account.baseUrl, session.accessToken, payload);
        }
        return;
      }
      if (existing != null) {
        await updateToken(
          account.baseUrl,
          session.accessToken,
          session.userId,
          tokenPayload(account, draft, existing.remoteId),
        );
        return;
      }
      await createToken(
        account.baseUrl,
        session.accessToken,
        session.userId,
        tokenPayload(account, draft),
      );
    });
    await syncAccount(account.id);
    if (existing != null) {
      return apiKeyById(existing.id);
    }
    final created = apiKeysForAccount(account.id).firstOrNull;
    if (created != null && account.platformType != PlatformType.sub2api) {
      try {
        created.key = await withAccountAuth(
          account,
          (session) => revealTokenKey(
            account.baseUrl,
            session.accessToken,
            session.userId,
            created.remoteId,
          ),
        );
        created.keyMasked = false;
        revealedKeys[created.id] = created.key;
        await persist();
      } catch (_) {
        created.keyMasked = true;
      }
    }
    _bump();
    return created;
  }

  Future<void> deleteApiKey(String id) async {
    final apiKey = apiKeyById(id);
    if (apiKey == null) {
      return;
    }
    final account = accountById(apiKey.accountId);
    if (account != null) {
      await withAccountAuth(account, (session) async {
        if (account.platformType == PlatformType.sub2api) {
          await deleteSub2Key(
            account.baseUrl,
            session.accessToken,
            apiKey.remoteId,
          );
        } else {
          await deleteToken(
            account.baseUrl,
            session.accessToken,
            session.userId,
            apiKey.remoteId,
          );
        }
      });
    }
    apiKeys = apiKeys.where((item) => item.id != id).toList();
    revealedKeys.remove(id);
    await persist();
    _bump();
  }

  Future<ApiKey?> toggleApiKeyStatus(String id) async {
    final apiKey = apiKeyById(id);
    if (apiKey == null ||
        apiKey.status == ApiKeyStatus.expired ||
        apiKey.status == ApiKeyStatus.exhausted) {
      return apiKey;
    }
    final account = accountById(apiKey.accountId);
    if (account == null) {
      throw ApiError(sessionExpiredMessage, 401);
    }
    final nextStatus = apiKey.status == ApiKeyStatus.disabled ? 1 : 2;
    await withAccountAuth(account, (session) async {
      if (account.platformType == PlatformType.sub2api) {
        await updateSub2Key(
          account.baseUrl,
          session.accessToken,
          apiKey.remoteId,
          {
            'status': apiKey.status == ApiKeyStatus.disabled
                ? 'active'
                : 'inactive',
          },
        );
        return;
      }
      await updateToken(account.baseUrl, session.accessToken, session.userId, {
        'id': apiKey.remoteId,
        'status': nextStatus,
      }, statusOnly: true);
    });
    await syncAccount(account.id);
    return apiKeyById(id);
  }

  Future<String> revealApiKey(String id) async {
    final apiKey = apiKeyById(id);
    if (apiKey == null) {
      throw ApiError('找不到这把密钥');
    }
    if (!apiKey.keyMasked && apiKey.key.isNotEmpty) {
      return apiKey.key;
    }
    if (revealedKeys[id] != null) {
      apiKey.key = revealedKeys[id]!;
      apiKey.keyMasked = false;
      return apiKey.key;
    }
    final account = accountById(apiKey.accountId);
    if (account == null) {
      throw ApiError(sessionExpiredMessage, 401);
    }
    final key = await withAccountAuth(account, (session) async {
      if (account.platformType == PlatformType.sub2api) {
        return (await fetchSub2KeyById(
              account.baseUrl,
              session.accessToken,
              apiKey.remoteId,
            )).key ??
            '';
      }
      return revealTokenKey(
        account.baseUrl,
        session.accessToken,
        session.userId,
        apiKey.remoteId,
      );
    });
    if (key.isEmpty) {
      throw ApiError('没能读取完整密钥，请稍后重试');
    }
    apiKey.key = key;
    apiKey.keyMasked = false;
    revealedKeys[id] = key;
    await persist();
    _bump();
    return key;
  }

  Future<KeyTestPrep> prepareKeyTest(String id, {String? baseUrl}) async {
    final apiKey = apiKeyById(id);
    if (apiKey == null) {
      throw ApiError('找不到这把密钥');
    }
    final account = accountById(apiKey.accountId);
    if (account == null) {
      throw ApiError('找不到对应账号');
    }
    final secret = await revealApiKey(id);
    final urls = apiCopyUrlsFor(account);
    if (urls.isEmpty) {
      throw ApiError('没有可测试的 API 地址');
    }
    final target = baseUrl != null && urls.contains(baseUrl)
        ? baseUrl
        : urls.first;
    final models = await runWithProxy(resolvedProxy(account.proxy), () async {
      var list = <String>[];
      Object? listError;
      try {
        list = await listApiKeyModels(baseUrl: target, apiKey: secret);
      } catch (error) {
        listError = error;
      }
      if (apiKey.modelLimits.isNotEmpty) {
        final allowed = apiKey.modelLimits.toSet();
        final filtered = list.where(allowed.contains).toList();
        list = filtered.isNotEmpty ? filtered : [...apiKey.modelLimits];
      }
      if (list.isEmpty) {
        list = [...modelsForGroup(account.id, apiKey.group)];
        if (list.isEmpty) {
          try {
            await loadGroupModels(account.id, apiKey.group);
          } catch (_) {}
          list = [...modelsForGroup(account.id, apiKey.group)];
        }
      }
      if (list.isEmpty && listError != null) {
        if (listError is ApiError) {
          throw listError;
        }
        throw ApiError(describeKeyProbeError(listError));
      }
      list.sort(
        (left, right) => left.toLowerCase().compareTo(right.toLowerCase()),
      );
      return list;
    });
    return KeyTestPrep(
      secret: secret,
      urls: urls,
      models: models,
      baseUrl: target,
    );
  }

  Future<ModelProbeResult> testKeyModel({
    required String accountId,
    required String secret,
    required String baseUrl,
    required String model,
    bool allowExpensive = false,
    ModelProbeKind? protocol,
  }) {
    final account = accountById(accountId);
    return runWithProxy(
      account == null ? null : resolvedProxy(account.proxy),
      () => probeModel(
        baseUrl: baseUrl,
        apiKey: secret,
        model: model,
        allowExpensive: allowExpensive,
        protocol: protocol,
      ),
    );
  }

  Future<void> saveCaptchaSolver(CaptchaSolverSettings next) async {
    settings.captchaSolver = next.copy();
    await persist();
    _bump();
  }

  Future<String?> solveTurnstileForSite(String baseUrl) async {
    final solver = settings.captchaSolver;
    final publicSettings = await fetchPublicSettings(baseUrl);
    final siteKey = publicSettings.turnstileSiteKey?.trim() ?? '';
    if (!publicSettings.turnstileEnabled || siteKey.isEmpty) {
      return null;
    }
    if (!solver.configured) {
      throw ApiError('该站点需要过人机验证。请到「我的 → 验证码服务」开启并填好 ClientKey');
    }
    return solveTurnstile(
      settings: solver,
      websiteUrl: joinUrl(baseUrl, '/login'),
      websiteKey: siteKey,
    );
  }

  Future<String?> solveNewApiTurnstileForSite(
    String baseUrl, {
    bool ignoreDisabled = false,
  }) async {
    final solver = settings.captchaSolver;
    final registerSettings = await fetchNewApiRegisterSettings(baseUrl);
    final siteKey = registerSettings.turnstileSiteKey;
    if (siteKey.isEmpty) {
      return null;
    }
    if (!ignoreDisabled && !registerSettings.turnstileEnabled) {
      return null;
    }
    if (!solver.configured) {
      throw ApiError('该站点需要过人机验证。请到「我的 → 验证码服务」开启并填好 ClientKey');
    }
    return solveTurnstile(
      settings: solver,
      websiteUrl: joinUrl(baseUrl, '/login'),
      websiteKey: siteKey,
    );
  }

  NetworkProxy? resolvedProxy(NetworkProxy proxy) {
    switch (proxy.mode) {
      case NetworkProxyMode.direct:
        return null;
      case NetworkProxyMode.custom:
        return proxy.isConfigured ? proxy : null;
      case NetworkProxyMode.followGlobal:
        return settings.networkProxy.isConfigured
            ? settings.networkProxy
            : null;
    }
  }

  Future<void> updateSettings(PrototypeSettings patch) async {
    settings = patch;
    HttpRequestLogger.instance.setEnabled(patch.developerLogEnabled);
    for (final account in accounts) {
      if (account.status != AccountStatus.pending) {
        updateAccountStatus(account);
      }
    }
    await persist();
    _bump();
  }

  String? quotaAlertMessage() {
    return describeQuotaAlert(
      enabled: settings.notificationEnabled,
      threshold: settings.lowQuotaThreshold,
      lowAccountNames: lowQuotaAccounts.map(displayAccountName).toList(),
    );
  }

  bool notifyQuotaAlerts() {
    final message = quotaAlertMessage();
    if (message == null) {
      return false;
    }
    notify(message, FeedbackType.warning);
    return true;
  }

  bool get hasAppUpdate {
    final release = latestRelease;
    return release != null && isAppVersionNewer(release.version, kAppVersion);
  }

  Future<void> checkAppUpdate({
    bool force = false,
    bool notifyIfAvailable = false,
  }) async {
    if (checkingUpdate) {
      return;
    }
    checkingUpdate = true;
    updateCheckError = null;
    _bump();
    try {
      final proxy = settings.networkProxy.isConfigured
          ? settings.networkProxy
          : null;
      final release = await runWithProxy(proxy, fetchLatestGithubRelease);
      latestRelease = release;
      if (notifyIfAvailable &&
          isAppVersionNewer(release.version, kAppVersion) &&
          _notifiedUpdateVersion != release.version) {
        _notifiedUpdateVersion = release.version;
        notify('发现新版本 v${release.version}', FeedbackType.text);
      }
    } catch (error) {
      updateCheckError = userFacingError(error, '暂时无法检查更新');
      if (force) {
        notify(updateCheckError!, FeedbackType.error);
      }
    } finally {
      checkingUpdate = false;
      _bump();
    }
  }

  void notify(String message, [FeedbackType type = FeedbackType.success]) {
    _feedbackTimer?.cancel();
    feedback = FeedbackState(visible: true, message: message, type: type);
    _bump();
    _feedbackTimer = Timer(const Duration(milliseconds: 2200), () {
      feedback.visible = false;
      _bump();
    });
  }

  void dismissFeedback() {
    _feedbackTimer?.cancel();
    feedback.visible = false;
    _bump();
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    super.dispose();
  }

  void setSearchTerm(String value) {
    searchTerm = value;
    _bump();
  }

  void setSelectedAccountStatus(String value) {
    selectedAccountStatus = value;
    _bump();
  }

  Account? get selectedKeysAccount {
    if (accounts.isEmpty) {
      return null;
    }
    return accountById(selectedKeysAccountId ?? '') ?? accounts.first;
  }

  void setSelectedKeysAccountId(String id) {
    final changed = selectedKeysAccountId != id;
    selectedKeysAccountId = id;
    if (changed) {
      _bump();
    }
    unawaited(loadTokenGroups(id).catchError((_) => <TokenGroupOption>[]));
  }
}
