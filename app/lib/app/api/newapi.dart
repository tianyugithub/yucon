import 'dart:convert';

import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/model_pricing.dart';
import 'package:vault/app/utils/quota.dart';

class NewApiUser {
  NewApiUser({
    required this.id,
    this.username,
    this.displayName,
    this.email,
    this.group,
    this.quota = 0,
    this.usedQuota = 0,
    this.requestCount = 0,
    this.status = 1,
  });

  final int id;
  final String? username;
  final String? displayName;
  final String? email;
  final String? group;
  final double quota;
  final double usedQuota;
  final int requestCount;
  final int status;

  factory NewApiUser.fromJson(Map<String, dynamic> json) => NewApiUser(
    id: readNumber(json['id']).toInt(),
    username: json['username']?.toString(),
    displayName: json['display_name']?.toString(),
    email: json['email']?.toString(),
    group: json['group']?.toString(),
    quota: readNumber(json['quota']),
    usedQuota: readNumber(json['used_quota']),
    requestCount: readNumber(json['request_count']).toInt(),
    status: readNumber(json['status'], 1).toInt(),
  );
}

class NewApiToken {
  NewApiToken({
    required this.id,
    this.name,
    this.key,
    this.status = 1,
    this.remainQuota = 0,
    this.usedQuota = 0,
    this.unlimitedQuota = false,
    this.expiredTime,
    this.createdTime,
    this.accessedTime,
    this.group,
    this.modelLimits,
    this.modelLimitsEnabled = false,
    this.allowIps,
    this.crossGroupRetry = false,
  });

  final int id;
  final String? name;
  final String? key;
  final int status;
  final double remainQuota;
  final double usedQuota;
  final bool unlimitedQuota;
  final num? expiredTime;
  final num? createdTime;
  final num? accessedTime;
  final String? group;
  final String? modelLimits;
  final bool modelLimitsEnabled;
  final String? allowIps;
  final bool crossGroupRetry;

  factory NewApiToken.fromJson(Map<String, dynamic> json) => NewApiToken(
    id: readNumber(json['id']).toInt(),
    name: json['name']?.toString(),
    key: json['key']?.toString(),
    status: readNumber(json['status'], 1).toInt(),
    remainQuota: readNumber(json['remain_quota']),
    usedQuota: readNumber(json['used_quota']),
    unlimitedQuota: json['unlimited_quota'] == true,
    expiredTime: json['expired_time'] as num?,
    createdTime: json['created_time'] as num?,
    accessedTime: json['accessed_time'] as num?,
    group: json['group']?.toString(),
    modelLimits: json['model_limits']?.toString(),
    modelLimitsEnabled: json['model_limits_enabled'] == true,
    allowIps: json['allow_ips']?.toString(),
    crossGroupRetry: json['cross_group_retry'] == true,
  );
}

class NewApiUsageLog {
  NewApiUsageLog({
    this.id,
    this.type,
    this.tokenName,
    this.tokenId,
    this.modelName,
    this.quota,
    this.promptTokens,
    this.completionTokens,
    this.createdAt,
    this.timeIso,
    this.ip,
    this.group,
    this.content,
    this.useTime,
    this.isStream,
  });

  final int? id;
  final int? type;
  final String? tokenName;
  final int? tokenId;
  final String? modelName;
  final double? quota;
  final int? promptTokens;
  final int? completionTokens;
  final num? createdAt;
  final String? timeIso;
  final String? ip;
  final String? group;
  final String? content;
  final num? useTime;
  final bool? isStream;

  factory NewApiUsageLog.fromJson(Map<String, dynamic> json) {
    final created = json['created_at'];
    return NewApiUsageLog(
      id: readNumber(json['id']).toInt(),
      type: json['type'] == null ? 2 : readNumber(json['type']).toInt(),
      tokenName: json['token_name']?.toString(),
      tokenId: (json['token_id'] as num?)?.toInt(),
      modelName: json['model_name']?.toString(),
      quota: readNumber(json['quota']),
      promptTokens: (json['prompt_tokens'] as num?)?.toInt(),
      completionTokens: (json['completion_tokens'] as num?)?.toInt(),
      createdAt: created is num ? created : num.tryParse(created?.toString() ?? ''),
      timeIso: createdAtToIso(created),
      ip: json['ip']?.toString(),
      group: json['group']?.toString(),
      content: json['content']?.toString(),
      useTime: json['use_time'] as num? ?? num.tryParse(json['use_time']?.toString() ?? ''),
      isStream: json['is_stream'] == true || json['is_stream'] == 1,
    );
  }
}

class NewApiLogStat {
  const NewApiLogStat({this.quota = 0, this.rpm = 0, this.tpm = 0});

  final double quota;
  final int rpm;
  final int tpm;

  factory NewApiLogStat.fromJson(Map<String, dynamic> json) => NewApiLogStat(
    quota: readNumber(json['quota']),
    rpm: readNumber(json['rpm']).round(),
    tpm: readNumber(json['tpm']).round(),
  );
}

class NewApiCheckinRecord {
  NewApiCheckinRecord({required this.checkinDate, required this.quotaAwarded});

  final String checkinDate;
  final double quotaAwarded;
}

class NewApiCheckinStats {
  NewApiCheckinStats({
    this.enabled = true,
    this.checkedInToday = false,
    this.records = const [],
  });

  final bool enabled;
  final bool checkedInToday;
  final List<NewApiCheckinRecord> records;
}

class SiteStatus {
  SiteStatus({
    required this.quotaPerUnit,
    required this.checkinEnabled,
    required this.systemName,
  });

  final double quotaPerUnit;
  final bool checkinEnabled;
  final String systemName;
}

class ConnectResult {
  ConnectResult({
    required this.baseUrl,
    required this.accessToken,
    required this.user,
    required this.quotaPerUnit,
    required this.checkinEnabled,
    this.refreshToken = '',
    this.cookies = '',
    this.systemName = '',
  });

  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final String cookies;
  final NewApiUser user;
  final double quotaPerUnit;
  final bool checkinEnabled;
  final String systemName;
}

class NewApiAuthRefresh {
  const NewApiAuthRefresh({
    required this.accessToken,
    this.cookies = '',
    this.userId = '',
  });

  final String accessToken;
  final String cookies;
  final String userId;
}

int? jwtExpiryUnix(String token) {
  final parts = token.trim().split('.');
  if (parts.length != 3) {
    return null;
  }
  try {
    var payload = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    final pad = payload.length % 4;
    if (pad != 0) {
      payload = payload.padRight(payload.length + (4 - pad), '=');
    }
    final decoded = jsonDecode(utf8.decode(base64Decode(payload)));
    if (decoded is Map && decoded['exp'] is num) {
      return (decoded['exp'] as num).toInt();
    }
  } catch (_) {}
  return null;
}

bool newApiAccessTokenIsFresh(String token, {int skewSeconds = 60}) {
  final value = token.trim();
  if (value.isEmpty || value.startsWith(cookieAuthPrefix)) {
    return false;
  }
  final exp = jwtExpiryUnix(value);
  if (exp == null) {
    return true;
  }
  return exp > DateTime.now().millisecondsSinceEpoch ~/ 1000 + skewSeconds;
}

Future<NewApiAuthRefresh?> refreshNewApiAccessToken(String baseUrl, String cookies) async {
  final cookieHeader = cookies.trim();
  if (cookieHeader.isEmpty) {
    return null;
  }

  Future<RequestResult<Map<String, dynamic>>> send() {
    return requestJsonDetailed<Map<String, dynamic>>(
      method: 'POST',
      baseUrl: baseUrl,
      path: '/api/user/auth/refresh',
      cookie: cookieHeader,
    );
  }

  RequestResult<Map<String, dynamic>> result;
  try {
    result = await send();
  } on ApiError catch (error) {
    if (error.status == 409) {
      await Future<void>.delayed(const Duration(milliseconds: 280));
      result = await send();
    } else if (error.status == 404 || error.status == 405) {
      return null;
    } else {
      rethrow;
    }
  }

  final payload = result.data;
  if (payload['success'] == false) {
    final code = payload['code']?.toString() ?? '';
    final message = payload['message']?.toString() ?? '';
    if (RegExp(r'AUTH_REFRESH|REFRESH_TOKEN|未登录|登录过期', caseSensitive: false)
        .hasMatch('$code $message')) {
      throw ApiError(friendlyAuthMessage(message.isEmpty ? '登录已过期，请重新登录' : message), 401);
    }
    throw ApiError(friendlyAuthMessage(message.isEmpty ? '刷新登录状态失败' : message), result.status);
  }

  final data = asRecord(payload['data']);
  final token = pickToken([data['access_token'], data['token']]);
  if (token.isEmpty) {
    return null;
  }
  final user = asUser(data['user']);
  return NewApiAuthRefresh(
    accessToken: token,
    cookies: mergeCookies([cookieHeader, result.cookies]),
    userId: user == null ? '' : '${user.id}',
  );
}

T unwrap<T>(Map<String, dynamic> payload, String fallbackMessage) {
  if (payload['success'] == false) {
    throw ApiError(friendlyAuthMessage(payload['message']?.toString() ?? fallbackMessage));
  }
  if (payload['data'] == null) {
    throw ApiError(friendlyAuthMessage(payload['message']?.toString() ?? fallbackMessage));
  }
  return payload['data'] as T;
}

String friendlyAuthMessage(String message) {
  if (message.contains('New-Api-User')) {
    return '该站点还需要填写用户 ID。请打开站点「个人设置」查看数字 ID，并和访问令牌一起填。';
  }
  if (message.contains('access token 无效') ||
      message.toLowerCase().contains('invalid access token')) {
    return '访问令牌无效。请重新生成，不要填写 sk- 开头的密钥。';
  }
  return message;
}

String pickToken(Iterable<Object?> values) {
  for (final value in values) {
    if (value is String &&
        value.trim().isNotEmpty &&
        value != 'null' &&
        value != 'undefined') {
      return value.trim();
    }
  }
  return '';
}

NewApiUser? asUser(Object? value) {
  final record = asRecord(value);
  final id = readNumber(record['id']).toInt();
  if (id == 0) {
    return null;
  }
  return NewApiUser.fromJson(record);
}

List<T> collectItems<T>(Object? data, T Function(Map<String, dynamic>) map) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((item) => map(Map<String, dynamic>.from(item)))
        .toList();
  }
  final record = asRecord(data);
  if (record['items'] is List) {
    return collectItems(record['items'], map);
  }
  if (record['data'] is List) {
    return collectItems(record['data'], map);
  }
  return [];
}

List<String> collectStrings(Object? data) {
  if (data is List) {
    return data.map((item) => item.toString()).where((item) => item.isNotEmpty).toList();
  }
  final record = asRecord(data);
  if (record['items'] is List) {
    return collectStrings(record['items']);
  }
  if (record['models'] is List) {
    return collectStrings(record['models']);
  }
  return [];
}

Future<SiteStatus> fetchSiteStatus(String baseUrl) async {
  try {
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: '/api/status',
    );
    final data = asRecord(payload['data']);
    return SiteStatus(
      quotaPerUnit: readNumber(data['quota_per_unit'], defaultQuotaPerUnit) == 0
          ? defaultQuotaPerUnit
          : readNumber(data['quota_per_unit'], defaultQuotaPerUnit),
      checkinEnabled: data['checkin_enabled'] == true,
      systemName: data['system_name']?.toString() ?? '',
    );
  } catch (_) {
    return SiteStatus(
      quotaPerUnit: defaultQuotaPerUnit,
      checkinEnabled: false,
      systemName: '',
    );
  }
}

String extractIssuedToken(Map<String, dynamic> payload) {
  final data = payload['data'];
  if (data is String) {
    return pickToken([data]);
  }
  final record = asRecord(data);
  return pickToken([record['access_token'], record['token'], record['key']]);
}

Future<NewApiUser> fetchUserWithAuth(
  String baseUrl,
  String token, {
  String? userId,
  String? cookie,
}) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/user/self',
    token: token,
    userId: userId,
    cookie: cookie,
  );
    return NewApiUser.fromJson(asRecord(unwrap(payload, '读取账号信息失败')));
}

Future<String> issueAccessToken(String baseUrl, String cookie, String userId) async {
  for (final method in ['GET', 'POST']) {
    try {
      final payload = await requestJson<Map<String, dynamic>>(
        baseUrl: baseUrl,
        path: '/api/user/token',
        method: method,
        cookie: cookie,
        userId: userId,
      );
      if (payload['success'] == false) {
        continue;
      }
      final token = extractIssuedToken(payload);
      if (token.isNotEmpty) {
        return token;
      }
    } catch (_) {}
  }
  return '';
}

Future<ConnectResult> connectAccount({
  required String baseUrl,
  String? username,
  String? password,
  String? accessToken,
  String? userId,
}) async {
  final normalized = normalizeBaseUrl(baseUrl);
  final status = await fetchSiteStatus(normalized);
  var token = accessToken?.trim() ?? '';
  final providedUserId = userId?.trim() ?? '';

  if (token.isEmpty) {
    final loginName = username?.trim() ?? '';
    final loginPassword = password ?? '';
    if (loginName.isEmpty || loginPassword.isEmpty) {
      throw ApiError('请填写用户名和密码，或改用访问令牌');
    }
    final login = await requestJsonDetailed<Map<String, dynamic>>(
      baseUrl: normalized,
      path: '/api/user/login',
      method: 'POST',
      data: {'username': loginName, 'password': loginPassword},
    );
    final raw = unwrap(login.data, '登录失败');
    final data = asRecord(raw);
    if (data['require_2fa'] == true) {
      throw ApiError('该账号开启了两步验证，请改用访问令牌连接');
    }
    final nestedUser = asUser(data['user']) ?? asUser(data);
    final resolvedUserId = '${nestedUser?.id ?? data['id'] ?? providedUserId}';
    final nested = asRecord(data['user']);
    token = pickToken([
      data['access_token'],
      data['token'],
      nested['access_token'],
      nested['token'],
      data['session'] is String ? data['session'] : null,
    ]);
    final sessionCookie = mergeCookies([login.cookies]);

    if (token.isNotEmpty) {
      final user = nestedUser ?? await fetchUserWithAuth(normalized, token, userId: resolvedUserId);
      return ConnectResult(
        baseUrl: normalized,
        accessToken: token,
        cookies: sessionCookie,
        user: user,
        quotaPerUnit: status.quotaPerUnit,
        checkinEnabled: status.checkinEnabled,
        systemName: status.systemName,
      );
    }

    if (sessionCookie.isNotEmpty) {
      try {
        final self = await requestJsonDetailed<Map<String, dynamic>>(
          baseUrl: normalized,
          path: '/api/user/self',
          cookie: sessionCookie,
          userId: resolvedUserId,
        );
        final user = NewApiUser.fromJson(asRecord(unwrap(self.data, '读取账号信息失败')));
        return ConnectResult(
          baseUrl: normalized,
          accessToken: asCookieAuth(mergeCookies([sessionCookie, self.cookies])),
          cookies: mergeCookies([sessionCookie, self.cookies]),
          user: user,
          quotaPerUnit: status.quotaPerUnit,
          checkinEnabled: status.checkinEnabled,
          systemName: status.systemName,
        );
      } catch (_) {
        final issued = await issueAccessToken(normalized, sessionCookie, resolvedUserId);
        if (issued.isNotEmpty) {
          final user = await fetchUserWithAuth(normalized, issued, userId: resolvedUserId);
          return ConnectResult(
            baseUrl: normalized,
            accessToken: issued,
            cookies: sessionCookie,
            user: user,
            quotaPerUnit: status.quotaPerUnit,
            checkinEnabled: status.checkinEnabled,
            systemName: status.systemName,
          );
        }
      }
    }

    throw ApiError(
      '登录成功，但没能保存登录状态。请到站点「个人设置」创建访问令牌后再连接。',
    );
  }

  try {
    final user = await fetchCurrentUser(
      normalized,
      token,
      providedUserId.isEmpty ? null : providedUserId,
    );
    return ConnectResult(
      baseUrl: normalized,
      accessToken: token,
      user: user,
      quotaPerUnit: status.quotaPerUnit,
      checkinEnabled: status.checkinEnabled,
      systemName: status.systemName,
    );
  } catch (error) {
    final text = error is ApiError ? error.message : error.toString();
    if (providedUserId.isEmpty && text.contains('New-Api-User')) {
      throw ApiError('请填写站点「个人设置」里的数字用户 ID，需和访问令牌一起使用。');
    }
    rethrow;
  }
}

Future<NewApiUser> fetchCurrentUser(
  String baseUrl,
  String accessToken,
  String? userId,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/user/self',
    token: accessToken,
    userId: userId,
  );
    return NewApiUser.fromJson(asRecord(unwrap(payload, '读取账号信息失败')));
}

Future<List<NewApiToken>> fetchTokens(
  String baseUrl,
  String accessToken,
  String userId,
) async {
  final tokens = <NewApiToken>[];
  for (final page in [1, 0]) {
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: '/api/token/?p=$page&size=100',
      token: accessToken,
      userId: userId,
    );
    final pageTokens = payload['success'] == false
        ? <NewApiToken>[]
        : collectItems(payload['data'], NewApiToken.fromJson);
    if (pageTokens.isNotEmpty) {
      tokens.addAll(pageTokens);
      break;
    }
    if (payload['success'] == false && page == 1) {
      continue;
    }
    if (page == 1 && pageTokens.isEmpty) {
      continue;
    }
    break;
  }
  return tokens;
}

Future<List<NewApiUsageLog>> fetchUsageLogs(
  String baseUrl,
  String accessToken,
  String userId,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/log/self?p=1&page_size=50&type=2',
    token: accessToken,
    userId: userId,
  );
  if (payload['success'] == false) {
    return [];
  }
  return parsePagedItemsFromPayload(
    payload,
    NewApiUsageLog.fromJson,
    page: 1,
    pageSize: 50,
  ).items;
}

Future<PagedItems<NewApiUsageLog>> fetchUsageLogsPage(
  String baseUrl,
  String accessToken,
  String userId, {
  int page = 1,
  int pageSize = 20,
  int type = 2,
  int? startTimestamp,
  int? endTimestamp,
  String? tokenName,
  String? modelName,
  String? group,
}) async {
  final query = buildQuery({
    'p': page,
    'page_size': pageSize,
    'type': type,
    'start_timestamp': startTimestamp,
    'end_timestamp': endTimestamp,
    'token_name': tokenName,
    'model_name': modelName,
    'group': group,
  });
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/log/self$query',
    token: accessToken,
    userId: userId,
  );
  if (payload['success'] == false) {
    throw ApiError(messageFromPayload(payload, '获取日志失败'));
  }
  return parsePagedItemsFromPayload(
    payload,
    NewApiUsageLog.fromJson,
    page: page,
    pageSize: pageSize,
  );
}

Future<NewApiLogStat?> fetchUsageLogStat(
  String baseUrl,
  String accessToken,
  String userId, {
  int type = 2,
  int? startTimestamp,
  int? endTimestamp,
  String? tokenName,
  String? modelName,
  String? group,
}) async {
  try {
    final query = buildQuery({
      'type': type,
      'start_timestamp': startTimestamp,
      'end_timestamp': endTimestamp,
      'token_name': tokenName,
      'model_name': modelName,
      'group': group,
    });
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: '/api/log/self/stat$query',
      token: accessToken,
      userId: userId,
    );
    if (payload['success'] == false) {
      return null;
    }
    return NewApiLogStat.fromJson(asRecord(payload['data']));
  } catch (_) {
    return null;
  }
}

Future<NewApiCheckinStats?> fetchCheckinStatus(
  String baseUrl,
  String accessToken,
  String userId,
) async {
  try {
    final month = DateTime.now().toIso8601String().substring(0, 7);
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: '/api/user/checkin?month=$month',
      token: accessToken,
      userId: userId,
    );
    if (payload['success'] == false) {
      return NewApiCheckinStats(enabled: false);
    }
    final data = asRecord(payload['data']);
    final stats = asRecord(data['stats'].runtimeType == Null ? data : data['stats'] ?? data);
    final source = stats.isEmpty ? data : stats;
    final records = ((source['records'] as List?) ?? (data['records'] as List?) ?? [])
        .whereType<Map>()
        .map(
          (item) => NewApiCheckinRecord(
            checkinDate: item['checkin_date']?.toString() ?? '',
            quotaAwarded: readNumber(item['quota_awarded']),
          ),
        )
        .toList();
    return NewApiCheckinStats(
      enabled: data['enabled'] != false,
      checkedInToday: source['checked_in_today'] == true || data['checked_in_today'] == true,
      records: records,
    );
  } catch (_) {
    return null;
  }
}

Future<({double quotaAwarded, String message})> doCheckin(
  String baseUrl,
  String accessToken,
  String userId,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/user/checkin',
    method: 'POST',
    token: accessToken,
    userId: userId,
    data: {},
  );
  if (payload['success'] == false) {
    throw ApiError(payload['message']?.toString() ?? '签到失败');
  }
  return (
    quotaAwarded: readNumber(asRecord(payload['data'])['quota_awarded']),
    message: payload['message']?.toString() ?? '签到成功',
  );
}

Future<void> createToken(
  String baseUrl,
  String accessToken,
  String userId,
  Map<String, dynamic> body,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/token/',
    method: 'POST',
    token: accessToken,
    userId: userId,
    data: body,
  );
  if (payload['success'] == false) {
    throw ApiError(payload['message']?.toString() ?? '创建密钥失败');
  }
}

Future<void> updateToken(
  String baseUrl,
  String accessToken,
  String userId,
  Map<String, dynamic> body, {
  bool statusOnly = false,
}) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: statusOnly ? '/api/token/?status_only=true' : '/api/token/',
    method: 'PUT',
    token: accessToken,
    userId: userId,
    data: body,
  );
  if (payload['success'] == false) {
    throw ApiError(payload['message']?.toString() ?? '更新密钥失败');
  }
}

Future<void> deleteToken(
  String baseUrl,
  String accessToken,
  String userId,
  int remoteId,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/token/$remoteId',
    method: 'DELETE',
    token: accessToken,
    userId: userId,
  );
  if (payload['success'] == false) {
    throw ApiError(payload['message']?.toString() ?? '删除密钥失败');
  }
}

Future<String> revealTokenKey(
  String baseUrl,
  String accessToken,
  String userId,
  int remoteId,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/token/$remoteId/key',
    method: 'POST',
    token: accessToken,
    userId: userId,
    data: {},
  );
  final key = asRecord(unwrap(payload, '读取密钥失败'))['key']?.toString() ?? '';
  if (key.isEmpty) {
    throw ApiError('没能读取完整密钥，请稍后重试');
  }
  return key;
}

TokenGroupOption toGroupOption(String name, String desc, Object? ratio) {
  return TokenGroupOption(
    name: name,
    desc: desc.isNotEmpty && desc != name
        ? desc
        : name == 'auto'
        ? '按系统自动分组规则路由'
        : (desc.isEmpty ? name : desc),
    ratio: ratio is num
        ? ratio.toDouble()
        : num.tryParse(ratio?.toString() ?? '')?.toDouble(),
    ratioLabel: formatGroupRatio(name == 'auto' ? '自动' : ratio),
  );
}

List<TokenGroupOption> parseUserGroups(Object? data) {
  final record = asRecord(data);
  final groups = <TokenGroupOption>[];
  record.forEach((name, value) {
    if (name.trim().isEmpty) {
      return;
    }
    if (value is String || value is num) {
      final text = value.toString();
      final ratioMatch = RegExp(r'倍率[:：]?\s*([0-9.]+|自动)').firstMatch(text);
      final desc = text.replaceFirst(RegExp(r'[，,]\s*倍率[:：]?.*'), '');
      groups.add(
        toGroupOption(
          name,
          desc,
          name == 'auto' ? '自动' : (ratioMatch?.group(1) ?? (value is num ? value : 1)),
        ),
      );
      return;
    }
    final item = asRecord(value);
    groups.add(
      toGroupOption(
        name,
        (item['desc'] ?? item['name'] ?? name).toString(),
        item['ratio'] ?? (name == 'auto' ? '自动' : 1),
      ),
    );
  });
  groups.sort((left, right) {
    if (left.name == 'auto') return -1;
    if (right.name == 'auto') return 1;
    if (left.name == 'default') return -1;
    if (right.name == 'default') return 1;
    return left.name.compareTo(right.name);
  });
  return groups;
}

Future<List<TokenGroupOption>> fetchUserGroups(
  String baseUrl,
  String accessToken,
  String userId,
) async {
  for (final path in ['/api/user/self/groups', '/api/user/groups']) {
    try {
      final payload = await requestJson<Map<String, dynamic>>(
        baseUrl: baseUrl,
        path: path,
        token: accessToken,
        userId: userId,
      );
      if (payload['success'] == false) {
        continue;
      }
      final groups = parseUserGroups(payload['data']);
      if (groups.isNotEmpty) {
        return groups;
      }
    } catch (_) {}
  }

  try {
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: '/api/pricing',
      token: accessToken,
      userId: userId,
    );
    final usable = asRecord(payload['usable_group'] ?? asRecord(payload['data'])['usable_group']);
    final ratios = asRecord(payload['group_ratio'] ?? asRecord(payload['data'])['group_ratio']);
    final groups = usable.keys
        .where((name) => name.isNotEmpty)
        .map(
          (name) => toGroupOption(
            name,
            usable[name]?.toString() ?? name,
            name == 'auto' ? '自动' : (ratios[name] ?? 1),
          ),
        )
        .toList();
    if (groups.isNotEmpty) {
      groups.sort((left, right) => left.name.compareTo(right.name));
      return groups;
    }
  } catch (_) {}
  return [];
}

Future<List<String>> fetchGroupModels(
  String baseUrl,
  String accessToken,
  String userId,
  String group,
) async {
  final suffix = group.isEmpty ? '' : '?group=${Uri.encodeQueryComponent(group)}';
  for (final path in [
    '/api/user/models$suffix',
    '/api/user/available_models$suffix',
    '/api/user/available_models',
  ]) {
    try {
      final payload = await requestJson<Map<String, dynamic>>(
        baseUrl: baseUrl,
        path: path,
        token: accessToken,
        userId: userId,
      );
      if (payload['success'] == false) {
        continue;
      }
      final models = collectStrings(payload['data']);
      if (models.isNotEmpty) {
        return models.toSet().toList();
      }
    } catch (_) {}
  }
  return [];
}

Future<SitePricingCatalog> fetchSitePricing(
  String baseUrl,
  String accessToken,
  String userId,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: '/api/pricing',
    token: accessToken,
    userId: userId,
  );
  if (payload['success'] == false) {
    throw ApiError(messageFromPayload(payload, '读取模型价格失败'));
  }
  return parseSitePricing(payload);
}
