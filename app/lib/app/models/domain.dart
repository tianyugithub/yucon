enum PlatformType { newapi, oneapi, sub2api }

enum AccountStatus {
  active,
  low,
  exhausted,
  disabled,
  pending,
  expired,
  blocked,
}

enum ApiKeyStatus { enabled, disabled, expired, exhausted }

enum FeedbackType { text, success, error, warning, loading }

enum AuthMode { password, accessToken }

enum NetworkProxyType {
  http,
  https,
  socks5;

  String get label => switch (this) {
    NetworkProxyType.http => 'HTTP',
    NetworkProxyType.https => 'HTTPS',
    NetworkProxyType.socks5 => 'SOCKS5',
  };

  static NetworkProxyType parse(String? name) {
    switch (name?.toLowerCase()) {
      case 'https':
        return NetworkProxyType.https;
      case 'socks5':
      case 'socks':
        return NetworkProxyType.socks5;
      default:
        return NetworkProxyType.http;
    }
  }
}

enum NetworkProxyMode { followGlobal, custom, direct }

class NetworkProxy {
  NetworkProxy({
    this.mode = NetworkProxyMode.direct,
    this.type = NetworkProxyType.http,
    this.host = '',
    this.port = 7890,
    this.username = '',
    this.password = '',
  });

  NetworkProxyMode mode;
  NetworkProxyType type;
  String host;
  int port;
  String username;
  String password;

  bool get isConfigured =>
      mode == NetworkProxyMode.custom &&
      host.trim().isNotEmpty &&
      port > 0 &&
      port <= 65535;

  bool get hasAuth => username.trim().isNotEmpty;

  String get addressText => host.trim().isEmpty ? '' : '${host.trim()}:$port';

  String get typeLabel => type.label;

  String get label {
    switch (mode) {
      case NetworkProxyMode.followGlobal:
        return '跟随全局';
      case NetworkProxyMode.custom:
        if (!isConfigured) {
          return '自定义';
        }
        return type == NetworkProxyType.http
            ? addressText
            : '$typeLabel · $addressText';
      case NetworkProxyMode.direct:
        return '直连';
    }
  }

  String get cacheKey =>
      '${type.name}|${host.trim()}|$port|${username.trim()}|$password';

  String get pacDirective {
    if (!isConfigured) {
      return 'DIRECT';
    }
    final target = '${host.trim()}:$port';
    return type == NetworkProxyType.socks5 ? 'SOCKS5 $target' : 'PROXY $target';
  }

  NetworkProxy copy() => NetworkProxy(
    mode: mode,
    type: type,
    host: host,
    port: port,
    username: username,
    password: password,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'enabled': mode == NetworkProxyMode.custom,
    'type': type.name,
    'host': host,
    'port': port,
    'username': username,
    'password': password,
  };

  factory NetworkProxy.fromJson(Object? json) {
    if (json is! Map) {
      return NetworkProxy();
    }
    final record = Map<String, dynamic>.from(json);
    final typeName = record['type']?.toString() ?? 'http';
    final modeName = record['mode']?.toString();
    final NetworkProxyMode mode;
    if (modeName == 'followGlobal') {
      mode = NetworkProxyMode.followGlobal;
    } else if (modeName == 'custom' || record['enabled'] == true) {
      mode = NetworkProxyMode.custom;
    } else {
      mode = NetworkProxyMode.direct;
    }
    return NetworkProxy(
      mode: mode,
      type: NetworkProxyType.parse(typeName),
      host: record['host']?.toString() ?? '',
      port: (record['port'] as num?)?.toInt() ?? 7890,
      username: record['username']?.toString() ?? '',
      password: record['password']?.toString() ?? '',
    );
  }

  factory NetworkProxy.fromAddress(
    String raw, {
    NetworkProxyType type = NetworkProxyType.http,
    String username = '',
    String password = '',
    NetworkProxyMode mode = NetworkProxyMode.custom,
  }) {
    var text = raw.trim();
    var parsedType = type;
    final lower = text.toLowerCase();
    if (lower.startsWith('socks5://') || lower.startsWith('socks://')) {
      parsedType = NetworkProxyType.socks5;
      text = text.replaceFirst(
        RegExp(r'^socks5?://', caseSensitive: false),
        '',
      );
    } else if (lower.startsWith('https://')) {
      parsedType = NetworkProxyType.https;
      text = text.replaceFirst(RegExp(r'^https://', caseSensitive: false), '');
    } else if (lower.startsWith('http://')) {
      parsedType = NetworkProxyType.http;
      text = text.replaceFirst(RegExp(r'^http://', caseSensitive: false), '');
    }
    text = text.split('/').first.trim();
    if (text.isEmpty) {
      return NetworkProxy(
        mode: mode,
        type: parsedType,
        username: username,
        password: password,
      );
    }
    if (RegExp(r'^\d{2,5}$').hasMatch(text)) {
      return NetworkProxy(
        mode: mode,
        type: parsedType,
        host: '127.0.0.1',
        port: int.parse(text),
        username: username,
        password: password,
      );
    }
    final colon = text.lastIndexOf(':');
    if (colon <= 0 || colon == text.length - 1) {
      return NetworkProxy(
        mode: mode,
        type: parsedType,
        host: text.replaceAll(RegExp(r'^\[|\]$'), ''),
        port: 7890,
        username: username,
        password: password,
      );
    }
    return NetworkProxy(
      mode: mode,
      type: parsedType,
      host: text.substring(0, colon).trim().replaceAll(RegExp(r'^\[|\]$'), ''),
      port: int.tryParse(text.substring(colon + 1).trim()) ?? 0,
      username: username,
      password: password,
    );
  }
}

class PlatformPreset {
  const PlatformPreset({
    required this.type,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.color,
    required this.lightColor,
    required this.supportsAccessToken,
    required this.supportsKeyModelLimits,
    required this.supportsCrossGroupRetry,
    required this.identityLabel,
    required this.identityPlaceholder,
  });

  final PlatformType type;
  final String label;
  final String shortLabel;
  final String description;
  final int color;
  final int lightColor;
  final bool supportsAccessToken;
  final bool supportsKeyModelLimits;
  final bool supportsCrossGroupRetry;
  final String identityLabel;
  final String identityPlaceholder;

  bool get supportsModelCatalog => supportsKeyModelLimits;
}

class BalancePoint {
  BalancePoint({required this.label, required this.value});

  String label;
  double value;

  Map<String, dynamic> toJson() => {'label': label, 'value': value};

  factory BalancePoint.fromJson(Map<String, dynamic> json) => BalancePoint(
    label: json['label']?.toString() ?? '',
    value: (json['value'] as num?)?.toDouble() ?? 0,
  );
}

class Account {
  Account({
    required this.id,
    required this.alias,
    required this.siteName,
    required this.baseUrl,
    required this.platformType,
    required this.authMode,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.email,
    required this.group,
    required this.quota,
    required this.usedQuota,
    required this.requestCount,
    required this.quotaPerUnit,
    required this.status,
    this.lastCheckin,
    required this.checkedInToday,
    required this.checkinEnabled,
    required this.tags,
    required this.trend,
    this.lastSyncedAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
    this.topupRatio = 1,
    List<String>? apiUrls,
    NetworkProxy? proxy,
    this.excludeFromTotalQuota = false,
  }) : apiUrls = apiUrls ?? [],
       proxy = proxy ?? NetworkProxy();

  String id;
  String alias;
  String siteName;
  String baseUrl;
  PlatformType platformType;
  AuthMode authMode;
  String userId;
  String username;
  String displayName;
  String email;
  String group;
  double quota;
  double usedQuota;
  int requestCount;
  double quotaPerUnit;
  AccountStatus status;
  String? lastCheckin;
  bool checkedInToday;
  bool checkinEnabled;
  List<String> tags;
  List<BalancePoint> trend;
  String? lastSyncedAt;
  String? lastError;
  String createdAt;
  String updatedAt;
  double topupRatio;
  List<String> apiUrls;
  NetworkProxy proxy;
  bool excludeFromTotalQuota;

  bool get needsRelogin => status == AccountStatus.expired;

  bool get networkBlocked => status == AccountStatus.blocked;

  bool get dnsPolluted =>
      status == AccountStatus.blocked && (lastError ?? '').contains('域名解析');

  Map<String, dynamic> toJson() => {
    'id': id,
    'alias': alias,
    'siteName': siteName,
    'baseUrl': baseUrl,
    'platformType': platformType.name,
    'authMode': authMode == AuthMode.accessToken ? 'access_token' : 'password',
    'userId': userId,
    'username': username,
    'displayName': displayName,
    'email': email,
    'group': group,
    'quota': quota,
    'usedQuota': usedQuota,
    'requestCount': requestCount,
    'quotaPerUnit': quotaPerUnit,
    'status': status.name,
    'lastCheckin': lastCheckin,
    'checkedInToday': checkedInToday,
    'checkinEnabled': checkinEnabled,
    'tags': tags,
    'trend': trend.map((item) => item.toJson()).toList(),
    'lastSyncedAt': lastSyncedAt,
    'lastError': lastError,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
    'topupRatio': topupRatio,
    'apiUrls': apiUrls,
    'proxy': proxy.toJson(),
    'excludeFromTotalQuota': excludeFromTotalQuota,
  };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id']?.toString() ?? '',
    alias: json['alias']?.toString() ?? '',
    siteName: json['siteName']?.toString() ?? '',
    baseUrl: json['baseUrl']?.toString() ?? '',
    platformType: parsePlatformType(json['platformType']?.toString()),
    authMode: json['authMode']?.toString() == 'access_token'
        ? AuthMode.accessToken
        : AuthMode.password,
    userId: json['userId']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    displayName: json['displayName']?.toString() ?? '',
    email: json['email']?.toString() ?? '',
    group: json['group']?.toString() ?? 'default',
    quota: (json['quota'] as num?)?.toDouble() ?? 0,
    usedQuota: (json['usedQuota'] as num?)?.toDouble() ?? 0,
    requestCount: (json['requestCount'] as num?)?.toInt() ?? 0,
    quotaPerUnit: (json['quotaPerUnit'] as num?)?.toDouble() ?? 500000,
    status: parseAccountStatus(json['status']?.toString()),
    lastCheckin: json['lastCheckin']?.toString(),
    checkedInToday: json['checkedInToday'] == true,
    checkinEnabled: json['checkinEnabled'] == true,
    tags: ((json['tags'] as List?) ?? [])
        .map((item) => item.toString())
        .toList(),
    trend: ((json['trend'] as List?) ?? [])
        .whereType<Map>()
        .map((item) => BalancePoint.fromJson(Map<String, dynamic>.from(item)))
        .toList(),
    lastSyncedAt: json['lastSyncedAt']?.toString(),
    lastError: json['lastError']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
    updatedAt: json['updatedAt']?.toString() ?? '',
    topupRatio: sanitizeTopupRatio(json['topupRatio']),
    apiUrls: ((json['apiUrls'] as List?) ?? [])
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(),
    proxy: NetworkProxy.fromJson(json['proxy']),
    excludeFromTotalQuota: json['excludeFromTotalQuota'] == true,
  );
}

class AccountSession {
  AccountSession({
    required this.accountId,
    required this.accessToken,
    required this.userId,
    this.refreshToken,
    this.cookies = '',
  });

  String accountId;
  String accessToken;
  String userId;
  String? refreshToken;
  String cookies;

  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'accessToken': accessToken,
    'userId': userId,
    'refreshToken': refreshToken,
    'cookies': cookies,
  };

  factory AccountSession.fromJson(Map<String, dynamic> json) => AccountSession(
    accountId: json['accountId']?.toString() ?? '',
    accessToken: json['accessToken']?.toString() ?? '',
    userId: json['userId']?.toString() ?? '',
    refreshToken: json['refreshToken']?.toString(),
    cookies: json['cookies']?.toString() ?? '',
  );
}

class ApiKey {
  ApiKey({
    required this.id,
    required this.accountId,
    required this.remoteId,
    required this.name,
    required this.key,
    required this.keyMasked,
    required this.status,
    required this.remainQuota,
    required this.usedQuota,
    required this.unlimitedQuota,
    this.expiresAt,
    required this.createdAt,
    this.accessedAt,
    required this.group,
    required this.modelLimits,
    required this.allowIps,
    required this.crossGroupRetry,
  });

  String id;
  String accountId;
  int remoteId;
  String name;
  String key;
  bool keyMasked;
  ApiKeyStatus status;
  double remainQuota;
  double usedQuota;
  bool unlimitedQuota;
  String? expiresAt;
  String createdAt;
  String? accessedAt;
  String group;
  List<String> modelLimits;
  List<String> allowIps;
  bool crossGroupRetry;

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'remoteId': remoteId,
    'name': name,
    'key': key,
    'keyMasked': keyMasked,
    'status': status.name,
    'remainQuota': remainQuota,
    'usedQuota': usedQuota,
    'unlimitedQuota': unlimitedQuota,
    'expiresAt': expiresAt,
    'createdAt': createdAt,
    'accessedAt': accessedAt,
    'group': group,
    'modelLimits': modelLimits,
    'allowIps': allowIps,
    'crossGroupRetry': crossGroupRetry,
  };

  factory ApiKey.fromJson(Map<String, dynamic> json) => ApiKey(
    id: json['id']?.toString() ?? '',
    accountId: json['accountId']?.toString() ?? '',
    remoteId: (json['remoteId'] as num?)?.toInt() ?? 0,
    name: json['name']?.toString() ?? '',
    key: json['key']?.toString() ?? '',
    keyMasked: json['keyMasked'] != false,
    status: parseApiKeyStatus(json['status']?.toString()),
    remainQuota: (json['remainQuota'] as num?)?.toDouble() ?? 0,
    usedQuota: (json['usedQuota'] as num?)?.toDouble() ?? 0,
    unlimitedQuota: json['unlimitedQuota'] == true,
    expiresAt: json['expiresAt']?.toString(),
    createdAt: json['createdAt']?.toString() ?? '',
    accessedAt: json['accessedAt']?.toString(),
    group: json['group']?.toString() ?? 'default',
    modelLimits: ((json['modelLimits'] as List?) ?? [])
        .map((item) => item.toString())
        .toList(),
    allowIps: ((json['allowIps'] as List?) ?? [])
        .map((item) => item.toString())
        .toList(),
    crossGroupRetry: json['crossGroupRetry'] == true,
  );
}

class CheckinLog {
  CheckinLog({
    required this.id,
    required this.accountId,
    required this.platformType,
    required this.time,
    required this.success,
    required this.message,
    this.reward,
    this.siteName = '',
    this.siteHost = '',
  });

  String id;
  String accountId;
  PlatformType platformType;
  String time;
  bool success;
  String message;
  double? reward;
  String siteName;
  String siteHost;

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'platformType': platformType.name,
    'time': time,
    'success': success,
    'message': message,
    'reward': reward,
    'siteName': siteName,
    'siteHost': siteHost,
  };

  factory CheckinLog.fromJson(Map<String, dynamic> json) => CheckinLog(
    id: json['id']?.toString() ?? '',
    accountId: json['accountId']?.toString() ?? '',
    platformType: parsePlatformType(json['platformType']?.toString()),
    time: json['time']?.toString() ?? '',
    success: json['success'] == true,
    message: json['message']?.toString() ?? '',
    reward: (json['reward'] as num?)?.toDouble(),
    siteName: json['siteName']?.toString() ?? '',
    siteHost: json['siteHost']?.toString() ?? '',
  );
}

class UsageLog {
  UsageLog({
    required this.id,
    required this.accountId,
    required this.platformType,
    required this.apiKeyId,
    required this.apiKeyName,
    required this.model,
    required this.time,
    required this.quotaCost,
    required this.promptTokens,
    required this.completionTokens,
    required this.success,
    this.ip = '',
    this.group = '',
    this.content = '',
    this.useTime = 0,
    this.isStream = false,
    this.type = 2,
    this.requestId = '',
    this.upstreamRequestId = '',
    this.channelName = '',
    this.username = '',
    Map<String, dynamic>? other,
  }) : other = other ?? {};

  String id;
  String accountId;
  PlatformType platformType;
  String apiKeyId;
  String apiKeyName;
  String model;
  String time;
  double quotaCost;
  int promptTokens;
  int completionTokens;
  bool success;
  String ip;
  String group;
  String content;
  num useTime;
  bool isStream;
  int type;
  String requestId;
  String upstreamRequestId;
  String channelName;
  String username;
  Map<String, dynamic> other;

  Map<String, dynamic> toJson() => {
    'id': id,
    'accountId': accountId,
    'platformType': platformType.name,
    'apiKeyId': apiKeyId,
    'apiKeyName': apiKeyName,
    'model': model,
    'time': time,
    'quotaCost': quotaCost,
    'promptTokens': promptTokens,
    'completionTokens': completionTokens,
    'success': success,
    'ip': ip,
    'group': group,
    'content': content,
    'useTime': useTime,
    'isStream': isStream,
    'type': type,
    'requestId': requestId,
    'upstreamRequestId': upstreamRequestId,
    'channelName': channelName,
    'username': username,
    if (other.isNotEmpty) 'other': other,
  };

  factory UsageLog.fromJson(Map<String, dynamic> json) => UsageLog(
    id: json['id']?.toString() ?? '',
    accountId: json['accountId']?.toString() ?? '',
    platformType: parsePlatformType(json['platformType']?.toString()),
    apiKeyId: json['apiKeyId']?.toString() ?? '',
    apiKeyName: json['apiKeyName']?.toString() ?? '',
    model: json['model']?.toString() ?? '',
    time: json['time']?.toString() ?? '',
    quotaCost: (json['quotaCost'] as num?)?.toDouble() ?? 0,
    promptTokens: (json['promptTokens'] as num?)?.toInt() ?? 0,
    completionTokens: (json['completionTokens'] as num?)?.toInt() ?? 0,
    success: json['success'] != false,
    ip: json['ip']?.toString() ?? '',
    group: json['group']?.toString() ?? '',
    content: json['content']?.toString() ?? '',
    useTime: json['useTime'] as num? ?? 0,
    isStream: json['isStream'] == true,
    type: (json['type'] as num?)?.toInt() ?? 2,
    requestId: json['requestId']?.toString() ?? '',
    upstreamRequestId: json['upstreamRequestId']?.toString() ?? '',
    channelName: json['channelName']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    other: _usageLogOtherFromJson(json['other']),
  );
}

Map<String, dynamic> _usageLogOtherFromJson(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return {};
}

enum UsageTimeRange { today, days7, days30, all }

class DateWindow {
  const DateWindow({this.startUnix, this.endUnix, this.startDate, this.endDate});

  final int? startUnix;
  final int? endUnix;
  final String? startDate;
  final String? endDate;

  bool get isUnbounded => startUnix == null && endUnix == null;
}

class UsageLogQuery {
  const UsageLogQuery({
    required this.accountId,
    this.page = 1,
    this.pageSize = 20,
    this.type = 2,
    this.range = UsageTimeRange.today,
    this.tokenName = '',
    this.modelName = '',
    this.group = '',
  });

  final String accountId;
  final int page;
  final int pageSize;
  final int type;
  final UsageTimeRange range;
  final String tokenName;
  final String modelName;
  final String group;

  bool get hasTextFilters =>
      tokenName.trim().isNotEmpty ||
      modelName.trim().isNotEmpty ||
      group.trim().isNotEmpty;
}

class UsageLogQueryResult {
  const UsageLogQueryResult({
    this.items = const [],
    this.total = 0,
    this.page = 1,
    this.pageSize = 20,
    this.quotaTotal = 0,
    this.rpm = 0,
    this.tpm = 0,
    this.statsAvailable = false,
    this.totalKnown = true,
  });

  final List<UsageLog> items;
  final int total;
  final int page;
  final int pageSize;
  final double quotaTotal;
  final int rpm;
  final int tpm;
  final bool statsAvailable;
  final bool totalKnown;

  int get pageCount {
    if (!totalKnown) {
      return hasNext ? page + 1 : page;
    }
    if (pageSize <= 0) {
      return 1;
    }
    if (total <= 0) {
      return 1;
    }
    return ((total + pageSize - 1) ~/ pageSize).clamp(1, 1 << 20);
  }

  bool get hasPrev => page > 1;

  bool get hasNext {
    if (totalKnown) {
      return page < pageCount;
    }
    return items.length >= pageSize && pageSize > 0;
  }
}

class PrototypeSettings {
  PrototypeSettings({
    this.lowQuotaThreshold = 5,
    this.notificationEnabled = true,
    this.recordIpLog = false,
    this.darkMode = false,
    this.developerLogEnabled = false,
    NetworkProxy? networkProxy,
  }) : networkProxy = networkProxy ?? NetworkProxy();

  double lowQuotaThreshold;
  bool notificationEnabled;
  bool recordIpLog;
  bool darkMode;
  bool developerLogEnabled;
  NetworkProxy networkProxy;

  PrototypeSettings copyWith({
    double? lowQuotaThreshold,
    bool? notificationEnabled,
    bool? recordIpLog,
    bool? darkMode,
    bool? developerLogEnabled,
    NetworkProxy? networkProxy,
  }) => PrototypeSettings(
    lowQuotaThreshold: lowQuotaThreshold ?? this.lowQuotaThreshold,
    notificationEnabled: notificationEnabled ?? this.notificationEnabled,
    recordIpLog: recordIpLog ?? this.recordIpLog,
    darkMode: darkMode ?? this.darkMode,
    developerLogEnabled: developerLogEnabled ?? this.developerLogEnabled,
    networkProxy: networkProxy ?? this.networkProxy.copy(),
  );

  Map<String, dynamic> toJson() => {
    'lowQuotaThreshold': lowQuotaThreshold,
    'notificationEnabled': notificationEnabled,
    'recordIpLog': recordIpLog,
    'darkMode': darkMode,
    'developerLogEnabled': developerLogEnabled,
    'networkProxy': networkProxy.toJson(),
  };

  factory PrototypeSettings.fromJson(Map<String, dynamic>? json) =>
      PrototypeSettings(
        lowQuotaThreshold:
            (json?['lowQuotaThreshold'] as num?)?.toDouble() ?? 5,
        notificationEnabled: json?['notificationEnabled'] != false,
        recordIpLog: json?['recordIpLog'] == true,
        darkMode: json?['darkMode'] == true,
        developerLogEnabled: json?['developerLogEnabled'] == true,
        networkProxy: NetworkProxy.fromJson(json?['networkProxy']),
      );
}

class FeedbackState {
  FeedbackState({
    this.visible = false,
    this.message = '',
    this.type = FeedbackType.text,
  });

  bool visible;
  String message;
  FeedbackType type;
}

class AccountDraft {
  AccountDraft({
    this.id,
    this.alias = '',
    this.siteName = '',
    this.baseUrl = '',
    this.platformType = PlatformType.newapi,
    this.authMode = AuthMode.password,
    this.username = '',
    this.password = '',
    this.accessToken = '',
    this.refreshToken,
    this.cookies = '',
    this.userId = '',
    List<String>? tags,
    this.turnstileToken,
    this.topupRatio = 1,
    List<String>? apiUrls,
    NetworkProxy? proxy,
    this.excludeFromTotalQuota = false,
  }) : tags = tags ?? [],
       apiUrls = apiUrls ?? [],
       proxy = proxy ?? NetworkProxy(mode: NetworkProxyMode.followGlobal);

  String? id;
  String alias;
  String siteName;
  String baseUrl;
  PlatformType platformType;
  AuthMode authMode;
  String username;
  String password;
  String accessToken;
  String? refreshToken;
  String cookies;
  String userId;
  List<String> tags;
  String? turnstileToken;
  double topupRatio;
  List<String> apiUrls;
  NetworkProxy proxy;
  bool excludeFromTotalQuota;
}

class ApiKeyDraft {
  ApiKeyDraft({
    this.id,
    this.accountId = '',
    this.name = '',
    this.unlimitedQuota = true,
    this.remainQuota = '10',
    this.expiresAt = '',
    this.group = 'default',
    this.modelLimitsText = '',
    this.allowIpsText = '',
    this.crossGroupRetry = false,
  });

  String? id;
  String accountId;
  String name;
  bool unlimitedQuota;
  String remainQuota;
  String expiresAt;
  String group;
  String modelLimitsText;
  String allowIpsText;
  bool crossGroupRetry;
}

class TokenGroupOption {
  TokenGroupOption({
    required this.name,
    required this.desc,
    this.ratio,
    required this.ratioLabel,
    this.remoteId,
  });

  String name;
  String desc;
  double? ratio;
  String ratioLabel;
  int? remoteId;
}

class CheckinSummary {
  const CheckinSummary({required this.message, required this.type});

  final String message;
  final FeedbackType type;
}

class TodayCheckinStatus {
  const TodayCheckinStatus({required this.done, required this.total});

  final int done;
  final int total;
}

PlatformType parsePlatformType(String? value) {
  switch (value) {
    case 'oneapi':
      return PlatformType.oneapi;
    case 'sub2api':
      return PlatformType.sub2api;
    default:
      return PlatformType.newapi;
  }
}

AccountStatus parseAccountStatus(String? value) {
  switch (value) {
    case 'low':
      return AccountStatus.low;
    case 'exhausted':
      return AccountStatus.exhausted;
    case 'disabled':
      return AccountStatus.disabled;
    case 'pending':
      return AccountStatus.pending;
    case 'expired':
      return AccountStatus.expired;
    case 'blocked':
      return AccountStatus.blocked;
    default:
      return AccountStatus.active;
  }
}

double sanitizeTopupRatio(num? value) {
  final ratio = value?.toDouble() ?? 1;
  return ratio > 0 && ratio.isFinite ? ratio : 1;
}

ApiKeyStatus parseApiKeyStatus(String? value) {
  switch (value) {
    case 'disabled':
      return ApiKeyStatus.disabled;
    case 'expired':
      return ApiKeyStatus.expired;
    case 'exhausted':
      return ApiKeyStatus.exhausted;
    default:
      return ApiKeyStatus.enabled;
  }
}
