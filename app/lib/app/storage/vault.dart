import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/model_pricing.dart';

class VaultStorage {
  static const _accounts = 'yucon.v2.accounts';
  static const _sessions = 'yucon.v2.sessions';
  static const _apiKeys = 'yucon.v2.apiKeys';
  static const _checkins = 'yucon.v2.checkinLogs';
  static const _usage = 'yucon.v2.usageLogs';
  static const _settings = 'yucon.v2.settings';
  static const _revealed = 'yucon.v2.revealedKeys';
  static const _passwords = 'yucon.v2.accountPasswords';
  static const _proxySecrets = 'yucon.v2.proxySecrets';
  static const _pricing = 'yucon.v2.pricingCatalogs';
  static const _tokenGroups = 'yucon.v2.tokenGroups';
  static const _tokenModels = 'yucon.v2.tokenModels';
  static const _googleIdentity = 'yucon.v2.googleIdentity';
  static const _githubIdentity = 'yucon.v2.githubIdentity';
  static const _qqMailIdentity = 'yucon.v2.qqMailIdentity';
  static const _identityLogins = 'yucon.v2.identityLogins';
  static const _identitySessions = 'yucon.v2.identitySessions';

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static SharedPreferences get prefs {
    final value = _prefs;
    if (value == null) {
      throw StateError('VaultStorage.init() must run first');
    }
    return value;
  }

  static List<T> _readList<T>(
    String key,
    T Function(Map<String, dynamic>) map,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => map(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<T>> _readSecureList<T>(
    String key,
    T Function(Map<String, dynamic>) map,
  ) async {
    final raw = await _secure.read(key: key);
    if (raw == null || raw.isEmpty) {
      return [];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return [];
      }
      return decoded
          .whereType<Map>()
          .map((item) => map(Map<String, dynamic>.from(item)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _write(String key, Object value) async {
    await prefs.setString(key, jsonEncode(value));
  }

  static Future<void> _writeSecure(String key, Object value) async {
    await _secure.write(key: key, value: jsonEncode(value));
  }

  static List<Account> loadAccounts() => _readList(_accounts, Account.fromJson);

  static Future<void> saveAccounts(List<Account> accounts) => _write(
    _accounts,
    accounts.map(_accountJsonWithoutProxyPassword).toList(),
  );

  static Future<List<AccountSession>> loadSessions() async {
    return _readSecureList(_sessions, AccountSession.fromJson);
  }

  static Future<void> saveSessions(List<AccountSession> sessions) =>
      _writeSecure(_sessions, sessions.map((item) => item.toJson()).toList());

  static Future<List<ApiKey>> loadApiKeys() async {
    final fromSecure = await _readSecureList(_apiKeys, ApiKey.fromJson);
    final fromPrefs = _readList(_apiKeys, ApiKey.fromJson);
    if (fromSecure.isNotEmpty) {
      if (fromPrefs.isNotEmpty) {
        await prefs.remove(_apiKeys);
      }
      return fromSecure;
    }
    if (fromPrefs.isNotEmpty) {
      await saveApiKeys(fromPrefs);
      await prefs.remove(_apiKeys);
    }
    return fromPrefs;
  }

  static Future<void> saveApiKeys(List<ApiKey> apiKeys) =>
      _writeSecure(_apiKeys, apiKeys.map((item) => item.toJson()).toList());

  static List<CheckinLog> loadCheckinLogs() =>
      _readList(_checkins, CheckinLog.fromJson);

  static Future<void> saveCheckinLogs(List<CheckinLog> logs) =>
      _write(_checkins, logs.map((item) => item.toJson()).toList());

  static List<UsageLog> loadUsageLogs() => _readList(_usage, UsageLog.fromJson);

  static Future<void> saveUsageLogs(List<UsageLog> logs) =>
      _write(_usage, logs.map((item) => item.toJson()).toList());

  static PrototypeSettings loadSettings() {
    final raw = prefs.getString(_settings);
    if (raw == null || raw.isEmpty) {
      return PrototypeSettings();
    }
    try {
      return PrototypeSettings.fromJson(asMap(jsonDecode(raw)));
    } catch (_) {
      return PrototypeSettings();
    }
  }

  static Future<void> saveSettings(PrototypeSettings settings) =>
      _write(_settings, _settingsJsonWithoutSecrets(settings));

  static Future<Map<String, String>> loadRevealedKeys() async {
    return _readSecureStringMap(_revealed);
  }

  static Future<void> saveRevealedKeys(Map<String, String> keys) =>
      _writeSecure(_revealed, keys);

  static Future<Map<String, String>> loadAccountPasswords() async {
    return _readSecureStringMap(_passwords);
  }

  static Future<void> saveAccountPasswords(Map<String, String> passwords) =>
      _writeSecure(_passwords, passwords);

  static Future<ProxySecrets> loadProxySecrets() async {
    final raw = await _secure.read(key: _proxySecrets);
    if (raw == null || raw.isEmpty) {
      return ProxySecrets.empty;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return ProxySecrets.empty;
      }
      return ProxySecrets.fromJson(asMap(decoded));
    } catch (_) {
      return ProxySecrets.empty;
    }
  }

  static Future<void> saveProxySecrets(ProxySecrets secrets) =>
      _writeSecure(_proxySecrets, secrets.toJson());

  static Future<WebIdentitySnapshot?> loadGoogleIdentity() =>
      _loadIdentity(_googleIdentity);

  static Future<void> saveGoogleIdentity(WebIdentitySnapshot? snapshot) =>
      _saveIdentity(_googleIdentity, snapshot);

  static Future<WebIdentitySnapshot?> loadGitHubIdentity() =>
      _loadIdentity(_githubIdentity);

  static Future<void> saveGitHubIdentity(WebIdentitySnapshot? snapshot) =>
      _saveIdentity(_githubIdentity, snapshot);

  static Future<void> clearQqMailIdentity() =>
      _secure.delete(key: _qqMailIdentity);

  static Future<IdentityLoginBundle> loadIdentityLogins() async {
    final raw = await _secure.read(key: _identityLogins);
    if (raw == null || raw.isEmpty) {
      return const IdentityLoginBundle();
    }
    try {
      return IdentityLoginBundle.fromJson(jsonDecode(raw));
    } catch (_) {
      return const IdentityLoginBundle();
    }
  }

  static Future<void> saveIdentityLogins(IdentityLoginBundle bundle) async {
    final accounts = [
      for (final account in bundle.accounts)
        if (account.provider.isNotEmpty && !account.isEmpty) account,
    ];
    if (accounts.isEmpty) {
      await _secure.delete(key: _identityLogins);
      return;
    }
    await _writeSecure(
      _identityLogins,
      IdentityLoginBundle(
        accounts: accounts,
        selectedIds: bundle.selectedIds,
      ).toJson(),
    );
  }

  static Future<Map<String, WebIdentitySnapshot>> loadIdentitySessions() async {
    final raw = await _secure.read(key: _identitySessions);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      final sessions = <String, WebIdentitySnapshot>{};
      for (final entry in decoded.entries) {
        final id = entry.key.toString();
        if (id.isEmpty || entry.value is! Map) {
          continue;
        }
        final snapshot = WebIdentitySnapshot.fromJson(asMap(entry.value));
        if (!snapshot.isConnected ||
            !isOAuthIdentityProvider(snapshot.provider)) {
          continue;
        }
        sessions[id] = snapshot.copyWith(
          accountId: snapshot.accountId.isEmpty ? id : snapshot.accountId,
        );
      }
      return sessions;
    } catch (_) {
      return {};
    }
  }

  static Future<void> saveIdentitySessions(
    Map<String, WebIdentitySnapshot> sessions,
  ) async {
    final payload = <String, Map<String, dynamic>>{};
    for (final entry in sessions.entries) {
      if (entry.key.isEmpty ||
          !entry.value.isConnected ||
          !isOAuthIdentityProvider(entry.value.provider)) {
        continue;
      }
      payload[entry.key] = entry.value.copyWith(accountId: entry.key).toJson();
    }
    if (payload.isEmpty) {
      await _secure.delete(key: _identitySessions);
      return;
    }
    await _writeSecure(_identitySessions, payload);
  }

  static Future<WebIdentitySnapshot?> _loadIdentity(String key) async {
    final raw = await _secure.read(key: key);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final snapshot = WebIdentitySnapshot.fromJson(asMap(decoded));
      return snapshot.isConnected ? snapshot : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveIdentity(
    String key,
    WebIdentitySnapshot? snapshot,
  ) async {
    if (snapshot == null || !snapshot.isConnected) {
      await _secure.delete(key: key);
      return;
    }
    await _writeSecure(key, snapshot.toJson());
  }

  static Map<String, SitePricingCatalog> loadPricingCatalogs() {
    final raw = prefs.getString(_pricing);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      final catalogs = <String, SitePricingCatalog>{};
      for (final entry in decoded.entries) {
        final accountId = entry.key.toString();
        if (accountId.isEmpty || entry.value is! Map) {
          continue;
        }
        final catalog = SitePricingCatalog.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
        if (catalog.isEmpty) {
          continue;
        }
        catalogs[accountId] = catalog;
      }
      return catalogs;
    } catch (_) {
      return {};
    }
  }

  static Future<void> savePricingCatalogs(
    Map<String, SitePricingCatalog> catalogs,
  ) => _write(_pricing, {
    for (final entry in catalogs.entries)
      if (!entry.value.isEmpty) entry.key: entry.value.toJson(),
  });

  static Map<String, List<TokenGroupOption>> loadTokenGroupCache() {
    final groups = _readStringKeyedMap(_tokenGroups, (value) {
      if (value is! List) {
        return <TokenGroupOption>[];
      }
      return value
          .whereType<Map>()
          .map(
            (item) =>
                TokenGroupOption.fromJson(Map<String, dynamic>.from(item)),
          )
          .where((group) => group.name.trim().isNotEmpty)
          .toList();
    });
    groups.removeWhere((_, value) => value.isEmpty);
    return groups;
  }

  static Future<void> saveTokenGroupCache(
    Map<String, List<TokenGroupOption>> groups,
  ) => _write(_tokenGroups, {
    for (final entry in groups.entries)
      if (entry.value.isNotEmpty)
        entry.key: entry.value.map((group) => group.toJson()).toList(),
  });

  static Map<String, List<String>> loadTokenModelCache() {
    return _readStringKeyedMap(_tokenModels, (value) {
      if (value is! List) {
        return <String>[];
      }
      return value
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList();
    });
  }

  static Future<void> saveTokenModelCache(Map<String, List<String>> models) =>
      _write(_tokenModels, {
        for (final entry in models.entries) entry.key: entry.value,
      });

  static Map<String, T> _readStringKeyedMap<T>(
    String key,
    T Function(Object? value) map,
  ) {
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      final result = <String, T>{};
      for (final entry in decoded.entries) {
        final id = entry.key.toString();
        if (id.isEmpty) {
          continue;
        }
        result[id] = map(entry.value);
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  static Future<Map<String, String>> _readSecureStringMap(String key) async {
    final raw = await _secure.read(key: key);
    if (raw == null || raw.isEmpty) {
      return {};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return {};
      }
      return decoded.map(
        (itemKey, value) => MapEntry(itemKey.toString(), value.toString()),
      );
    } catch (_) {
      return {};
    }
  }

  static Map<String, dynamic> _accountJsonWithoutProxyPassword(
    Account account,
  ) {
    final json = account.toJson();
    final proxy = asMap(json['proxy']);
    proxy['password'] = '';
    json['proxy'] = proxy;
    return json;
  }

  static Map<String, dynamic> _settingsJsonWithoutSecrets(
    PrototypeSettings settings,
  ) {
    final json = settings.toJson();
    final proxy = asMap(json['networkProxy']);
    proxy['password'] = '';
    json['networkProxy'] = proxy;
    final captcha = asMap(json['captchaSolver']);
    captcha['clientKey'] = '';
    captcha['clientKeys'] = <String, String>{};
    json['captchaSolver'] = captcha;
    return json;
  }

  static Map<String, dynamic> asMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return {};
  }
}

class ProxySecrets {
  const ProxySecrets({
    this.global = '',
    this.accounts = const {},
    this.captcha = '',
    this.captchaKeys = const {},
  });

  static const empty = ProxySecrets();

  final String global;
  final Map<String, String> accounts;
  final String captcha;
  final Map<String, String> captchaKeys;

  Map<String, dynamic> toJson() => {
    'global': global,
    'accounts': accounts,
    if (captcha.isNotEmpty) 'captcha': captcha,
    if (captchaKeys.isNotEmpty) 'captchaKeys': captchaKeys,
  };

  factory ProxySecrets.fromJson(Map<String, dynamic> json) {
    final accountsRaw = json['accounts'];
    final accounts = <String, String>{};
    if (accountsRaw is Map) {
      for (final entry in accountsRaw.entries) {
        final value = entry.value.toString();
        if (value.isNotEmpty) {
          accounts[entry.key.toString()] = value;
        }
      }
    }
    final captchaKeysRaw = json['captchaKeys'];
    final captchaKeys = <String, String>{};
    if (captchaKeysRaw is Map) {
      for (final entry in captchaKeysRaw.entries) {
        final value = entry.value.toString();
        if (value.isNotEmpty) {
          captchaKeys[entry.key.toString()] = value;
        }
      }
    }
    return ProxySecrets(
      global: json['global']?.toString() ?? '',
      accounts: accounts,
      captcha: json['captcha']?.toString() ?? '',
      captchaKeys: captchaKeys,
    );
  }
}
