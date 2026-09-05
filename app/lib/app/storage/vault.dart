import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vault/app/models/domain.dart';

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

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
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

  static List<T> _readList<T>(String key, T Function(Map<String, dynamic>) map) {
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
      _writeSecure(
        _sessions,
        sessions.map((item) => item.toJson()).toList(),
      );

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
      _write(_settings, _settingsJsonWithoutProxyPassword(settings));

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

  static Map<String, dynamic> _accountJsonWithoutProxyPassword(Account account) {
    final json = account.toJson();
    final proxy = asMap(json['proxy']);
    proxy['password'] = '';
    json['proxy'] = proxy;
    return json;
  }

  static Map<String, dynamic> _settingsJsonWithoutProxyPassword(
    PrototypeSettings settings,
  ) {
    final json = settings.toJson();
    final proxy = asMap(json['networkProxy']);
    proxy['password'] = '';
    json['networkProxy'] = proxy;
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
  });

  static const empty = ProxySecrets();

  final String global;
  final Map<String, String> accounts;

  Map<String, dynamic> toJson() => {
    'global': global,
    'accounts': accounts,
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
    return ProxySecrets(
      global: json['global']?.toString() ?? '',
      accounts: accounts,
    );
  }
}
