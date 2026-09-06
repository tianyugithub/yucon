import 'dart:convert';

import 'package:vault/app/identity/web_identity.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/storage/vault.dart';

const vaultBackupFormat = 'yucon-vault';
const vaultBackupVersion = 3;
const vaultBackupExtension = 'json';

class VaultBackupException implements Exception {
  VaultBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum VaultBackupApplyMode { merge, replace }

class VaultSnapshot {
  VaultSnapshot({
    required this.exportedAt,
    required this.accounts,
    required this.sessions,
    required this.apiKeys,
    required this.revealedKeys,
    required this.checkinLogs,
    required this.usageLogs,
    required this.settings,
    this.accountPasswords = const {},
    this.identityLogins = const [],
    this.identityLoginSelectedIds = const {},
    this.identitySessions = const {},
    this.version = vaultBackupVersion,
  });

  final DateTime exportedAt;
  final int version;
  final List<Account> accounts;
  final List<AccountSession> sessions;
  final List<ApiKey> apiKeys;
  final Map<String, String> revealedKeys;
  final List<CheckinLog> checkinLogs;
  final List<UsageLog> usageLogs;
  final PrototypeSettings settings;
  final Map<String, String> accountPasswords;
  final List<IdentityLoginAccount> identityLogins;
  final Map<String, String> identityLoginSelectedIds;
  final Map<String, WebIdentitySnapshot> identitySessions;

  int get sessionCount =>
      sessions.where((session) => session.accessToken.isNotEmpty).length;

  int get identitySessionCount =>
      identitySessions.values.where((item) => item.isConnected).length;

  String get summaryLabel {
    final parts = <String>['${accounts.length} 个账号'];
    if (apiKeys.isNotEmpty) {
      parts.add('${apiKeys.length} 个密钥');
    }
    if (sessionCount > 0) {
      parts.add('$sessionCount 个登录状态');
    }
    if (accountPasswords.isNotEmpty) {
      parts.add('${accountPasswords.length} 个登录密码');
    }
    if (identityLogins.isNotEmpty) {
      parts.add('${identityLogins.length} 个身份账号');
    }
    if (identitySessionCount > 0) {
      parts.add('$identitySessionCount 个身份登录');
    }
    return parts.join(' · ');
  }

  Map<String, dynamic> toJson() => {
    'format': vaultBackupFormat,
    'version': version,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'accounts': accounts.map((item) => item.toJson()).toList(),
    'sessions': sessions.map((item) => item.toJson()).toList(),
    'apiKeys': apiKeys.map((item) => item.toJson()).toList(),
    'revealedKeys': revealedKeys,
    'checkinLogs': checkinLogs.map((item) => item.toJson()).toList(),
    'usageLogs': usageLogs.map((item) => item.toJson()).toList(),
    'settings': settings.toJson(),
    'accountPasswords': accountPasswords,
    'identityLogins': identityLogins.map((item) => item.toJson()).toList(),
    'identityLoginSelected': identityLoginSelectedIds,
    'identitySessions': {
      for (final entry in identitySessions.entries)
        if (entry.key.isNotEmpty && entry.value.isConnected)
          entry.key: entry.value.copyWith(accountId: entry.key).toJson(),
    },
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  VaultSnapshot clone() => VaultSnapshot.decode(encode());

  static VaultSnapshot decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      throw VaultBackupException('备份文件是空的');
    }
    final Object decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      throw VaultBackupException('备份文件已损坏，打不开');
    }
    if (decoded is! Map) {
      throw VaultBackupException('这不是钥仓备份文件');
    }
    final record = VaultStorage.asMap(decoded);
    final format = record['format']?.toString();
    if (format != null && format != vaultBackupFormat) {
      throw VaultBackupException('这不是钥仓备份文件');
    }
    if (format == null && record['accounts'] is! List) {
      throw VaultBackupException('这不是钥仓备份文件');
    }
    if (record['encrypted'] == true) {
      throw VaultBackupException('这份备份已加密，需要密码');
    }
    final exportedAt =
        DateTime.tryParse(record['exportedAt']?.toString() ?? '')?.toUtc() ??
        DateTime.now().toUtc();
    final accounts = _mapList(record['accounts'], Account.fromJson)
        .where(
          (account) =>
              account.id.isNotEmpty && account.baseUrl.trim().isNotEmpty,
        )
        .toList();
    final accountIds = accounts.map((account) => account.id).toSet();
    final apiKeys = _mapList(record['apiKeys'], ApiKey.fromJson)
        .where(
          (apiKey) =>
              accountIds.contains(apiKey.accountId) && apiKey.id.isNotEmpty,
        )
        .toList();
    final apiKeyIds = apiKeys.map((apiKey) => apiKey.id).toSet();
    final revealed = <String, String>{};
    final revealedRaw = record['revealedKeys'];
    if (revealedRaw is Map) {
      for (final entry in revealedRaw.entries) {
        final key = entry.key.toString();
        final value = entry.value.toString();
        if (apiKeyIds.contains(key) && value.isNotEmpty) {
          revealed[key] = value;
        }
      }
    }
    return VaultSnapshot(
      exportedAt: exportedAt,
      version: (record['version'] as num?)?.toInt() ?? 1,
      accounts: accounts,
      sessions: _mapList(record['sessions'], AccountSession.fromJson)
          .where(
            (session) =>
                accountIds.contains(session.accountId) &&
                session.accessToken.isNotEmpty,
          )
          .toList(),
      apiKeys: apiKeys,
      revealedKeys: revealed,
      checkinLogs: _mapList(
        record['checkinLogs'],
        CheckinLog.fromJson,
      ).where((log) => accountIds.contains(log.accountId)).toList(),
      usageLogs: _mapList(
        record['usageLogs'],
        UsageLog.fromJson,
      ).where((log) => accountIds.contains(log.accountId)).toList(),
      settings: PrototypeSettings.fromJson(
        record['settings'] is Map
            ? VaultStorage.asMap(record['settings'])
            : null,
      ),
      accountPasswords: _stringMap(record['accountPasswords'], accountIds),
      identityLogins: _identityLogins(record['identityLogins']),
      identityLoginSelectedIds: _identitySelected(
        record['identityLoginSelected'],
      ),
      identitySessions: _identitySessions(record['identitySessions']),
    );
  }

  static VaultSnapshot merge(VaultSnapshot current, VaultSnapshot incoming) {
    final accounts = _mergeBy(
      current.accounts,
      incoming.accounts,
      (item) => item.id,
    );
    final accountIds = accounts.map((account) => account.id).toSet();
    final sessions = _mergeBy(
      current.sessions,
      incoming.sessions,
      (item) => item.accountId,
    ).where((session) => accountIds.contains(session.accountId)).toList();
    final apiKeys = _mergeBy(
      current.apiKeys,
      incoming.apiKeys,
      (item) => item.id,
    ).where((apiKey) => accountIds.contains(apiKey.accountId)).toList();
    final apiKeyIds = apiKeys.map((apiKey) => apiKey.id).toSet();
    final revealed = Map<String, String>.from(current.revealedKeys)
      ..addAll(incoming.revealedKeys);
    revealed.removeWhere(
      (key, value) => !apiKeyIds.contains(key) || value.isEmpty,
    );
    final passwords = Map<String, String>.from(current.accountPasswords)
      ..addAll(incoming.accountPasswords);
    passwords.removeWhere(
      (key, value) => !accountIds.contains(key) || value.isEmpty,
    );
    final identityLogins = _mergeBy(
      current.identityLogins,
      incoming.identityLogins,
      (item) => item.id,
    ).where((item) => item.id.isNotEmpty && !item.isEmpty).toList();
    final selected = Map<String, String>.from(current.identityLoginSelectedIds)
      ..addAll(incoming.identityLoginSelectedIds);
    selected.removeWhere(
      (provider, id) => !isOAuthIdentityProvider(provider) || id.isEmpty,
    );
    final identitySessions = <String, WebIdentitySnapshot>{
      ...current.identitySessions,
      ...incoming.identitySessions,
    };
    identitySessions.removeWhere(
      (id, snapshot) =>
          id.isEmpty ||
          !snapshot.isConnected ||
          !isOAuthIdentityProvider(snapshot.provider),
    );
    return VaultSnapshot(
      exportedAt: incoming.exportedAt,
      accounts: accounts,
      sessions: sessions,
      apiKeys: apiKeys,
      revealedKeys: revealed,
      checkinLogs: _mergeBy(
        current.checkinLogs,
        incoming.checkinLogs,
        (item) => item.id,
      ).where((log) => accountIds.contains(log.accountId)).toList(),
      usageLogs: _mergeBy(
        current.usageLogs,
        incoming.usageLogs,
        (item) => item.id,
      ).where((log) => accountIds.contains(log.accountId)).toList(),
      settings: _mergeSettings(current.settings, incoming.settings),
      accountPasswords: passwords,
      identityLogins: identityLogins,
      identityLoginSelectedIds: selected,
      identitySessions: identitySessions,
    );
  }
}

class BackupFileInfo {
  BackupFileInfo({
    required this.path,
    required this.name,
    required this.modifiedAt,
    this.exportedAt,
    this.accountCount = 0,
    this.keyCount = 0,
    this.encrypted = false,
    this.readable = true,
  });

  final String path;
  final String name;
  final DateTime modifiedAt;
  final DateTime? exportedAt;
  final int accountCount;
  final int keyCount;
  final bool encrypted;
  final bool readable;

  String get detailLabel {
    if (!readable) {
      return '无法识别这份文件';
    }
    final parts = <String>[if (encrypted) '已加密', '$accountCount 个账号'];
    if (keyCount > 0) {
      parts.add('$keyCount 个密钥');
    }
    return parts.join(' · ');
  }
}

String backupFileStem(DateTime time) {
  final local = time.toLocal();
  String pad(int value) => value.toString().padLeft(2, '0');
  return '钥仓备份-${local.year}${pad(local.month)}${pad(local.day)}-'
      '${pad(local.hour)}${pad(local.minute)}${pad(local.second)}';
}

class BackupPeek {
  BackupPeek({
    required this.encrypted,
    this.exportedAt,
    this.accountCount = 0,
    this.keyCount = 0,
  });

  final bool encrypted;
  final DateTime? exportedAt;
  final int accountCount;
  final int keyCount;
}

BackupPeek peekBackup(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    throw VaultBackupException('备份文件是空的');
  }
  final Object decoded;
  try {
    decoded = jsonDecode(text);
  } catch (_) {
    throw VaultBackupException('备份文件已损坏，打不开');
  }
  if (decoded is! Map) {
    throw VaultBackupException('这不是钥仓备份文件');
  }
  final record = VaultStorage.asMap(decoded);
  final format = record['format']?.toString();
  if (format != null && format != vaultBackupFormat) {
    throw VaultBackupException('这不是钥仓备份文件');
  }
  if (record['encrypted'] == true) {
    final summary = record['summary'] is Map
        ? VaultStorage.asMap(record['summary'])
        : <String, dynamic>{};
    return BackupPeek(
      encrypted: true,
      exportedAt: DateTime.tryParse(record['exportedAt']?.toString() ?? '')
          ?.toUtc(),
      accountCount: (summary['accounts'] as num?)?.toInt() ?? 0,
      keyCount: (summary['keys'] as num?)?.toInt() ?? 0,
    );
  }
  final snapshot = VaultSnapshot.decode(text);
  return BackupPeek(
    encrypted: false,
    exportedAt: snapshot.exportedAt,
    accountCount: snapshot.accounts.length,
    keyCount: snapshot.apiKeys.length,
  );
}

List<T> _mapList<T>(Object? raw, T Function(Map<String, dynamic>) map) {
  if (raw is! List) {
    return [];
  }
  return raw
      .whereType<Map>()
      .map((item) => map(VaultStorage.asMap(item)))
      .toList();
}

List<T> _mergeBy<T>(
  List<T> current,
  List<T> incoming,
  String Function(T item) idOf,
) {
  final merged = <String, T>{};
  for (final item in current) {
    final id = idOf(item);
    if (id.isNotEmpty) {
      merged[id] = item;
    }
  }
  for (final item in incoming) {
    final id = idOf(item);
    if (id.isNotEmpty) {
      merged[id] = item;
    }
  }
  return merged.values.toList();
}

Map<String, String> _stringMap(Object? raw, Set<String> allowedIds) {
  if (raw is! Map) {
    return {};
  }
  final mapped = <String, String>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString();
    final value = entry.value.toString();
    if (allowedIds.contains(key) && value.isNotEmpty) {
      mapped[key] = value;
    }
  }
  return mapped;
}

List<IdentityLoginAccount> _identityLogins(Object? raw) {
  return _mapList(raw, IdentityLoginAccount.fromJson)
      .where(
        (item) =>
            item.id.isNotEmpty &&
            !item.isEmpty &&
            isOAuthIdentityProvider(item.provider),
      )
      .toList();
}

Map<String, String> _identitySelected(Object? raw) {
  if (raw is! Map) {
    return {};
  }
  final mapped = <String, String>{};
  for (final entry in raw.entries) {
    final provider = entry.key.toString();
    final id = entry.value.toString();
    if (isOAuthIdentityProvider(provider) && id.isNotEmpty) {
      mapped[provider] = id;
    }
  }
  return mapped;
}

Map<String, WebIdentitySnapshot> _identitySessions(Object? raw) {
  if (raw is! Map) {
    return {};
  }
  final sessions = <String, WebIdentitySnapshot>{};
  for (final entry in raw.entries) {
    final id = entry.key.toString();
    if (id.isEmpty || entry.value is! Map) {
      continue;
    }
    final snapshot = WebIdentitySnapshot.fromJson(
      VaultStorage.asMap(entry.value),
    ).copyWith(accountId: id);
    if (!snapshot.isConnected || !isOAuthIdentityProvider(snapshot.provider)) {
      continue;
    }
    sessions[id] = snapshot;
  }
  return sessions;
}

PrototypeSettings _mergeSettings(
  PrototypeSettings current,
  PrototypeSettings incoming,
) {
  final proxy = current.networkProxy.copy();
  if (proxy.password.trim().isEmpty &&
      incoming.networkProxy.password.trim().isNotEmpty) {
    proxy.password = incoming.networkProxy.password;
  }
  return current.copyWith(
    networkProxy: proxy,
    captchaSolver: _mergeCaptcha(current.captchaSolver, incoming.captchaSolver),
  );
}

CaptchaSolverSettings _mergeCaptcha(
  CaptchaSolverSettings current,
  CaptchaSolverSettings incoming,
) {
  final keys = <CaptchaSolverType, String>{};
  for (final type in CaptchaSolverType.values) {
    final incomingKey = incoming.keyFor(type);
    final currentKey = current.keyFor(type);
    if (incomingKey.isNotEmpty) {
      keys[type] = incomingKey;
    } else if (currentKey.isNotEmpty) {
      keys[type] = currentKey;
    }
  }
  return CaptchaSolverSettings(
    enabled: current.configured ? current.enabled : incoming.enabled,
    type: current.configured ? current.type : incoming.type,
    clientKeys: keys,
  );
}
