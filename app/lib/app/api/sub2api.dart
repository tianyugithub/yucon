import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/newapi.dart';
import 'package:vault/app/models/domain.dart';
import 'package:vault/app/utils/quota.dart';

class Sub2PublicSettings {
  Sub2PublicSettings({
    this.turnstileEnabled = false,
    this.turnstileSiteKey,
    this.siteName,
    this.registrationEnabled = true,
    this.emailVerifyEnabled = false,
    this.emailSuffixWhitelist = const [],
  });

  final bool turnstileEnabled;
  final String? turnstileSiteKey;
  final String? siteName;
  final bool registrationEnabled;
  final bool emailVerifyEnabled;
  final List<String> emailSuffixWhitelist;

  factory Sub2PublicSettings.fromJson(Map<String, dynamic> json) {
    final data = _unwrap(json);
    final siteName = data['site_name']?.toString().trim();
    final whitelist = data['registration_email_suffix_whitelist'];
    return Sub2PublicSettings(
      turnstileEnabled: data['turnstile_enabled'] == true,
      turnstileSiteKey: data['turnstile_site_key']?.toString(),
      siteName: (siteName == null || siteName.isEmpty) ? null : siteName,
      registrationEnabled: data['registration_enabled'] != false,
      emailVerifyEnabled: data['email_verify_enabled'] == true,
      emailSuffixWhitelist: whitelist is List
          ? [
              for (final item in whitelist)
                if (item.toString().trim().isNotEmpty) item.toString().trim(),
            ]
          : const [],
    );
  }

  static Map<String, dynamic> _unwrap(Map<String, dynamic> json) {
    final nested = json['data'];
    if (nested is Map &&
        (nested.containsKey('site_name') ||
            nested.containsKey('turnstile_enabled') ||
            nested.containsKey('turnstile_site_key'))) {
      return asRecord(nested);
    }
    return json;
  }
}

bool _looksLikeSub2PublicSettings(Map<String, dynamic> json) {
  return json.containsKey('turnstile_enabled') ||
      json.containsKey('turnstile_site_key') ||
      json.containsKey('site_name');
}

SiteStatus siteStatusFromSub2Settings(Sub2PublicSettings settings) {
  return SiteStatus(
    quotaPerUnit: defaultQuotaPerUnit,
    checkinEnabled: false,
    systemName: settings.siteName?.trim() ?? '',
  );
}

Future<SiteStatus> fetchSub2SiteStatus(String baseUrl) async {
  try {
    final settings = await fetchPublicSettings(baseUrl);
    return siteStatusFromSub2Settings(settings);
  } catch (_) {
    return SiteStatus(
      quotaPerUnit: defaultQuotaPerUnit,
      checkinEnabled: false,
      systemName: '',
    );
  }
}

class Sub2User {
  Sub2User({
    required this.id,
    this.username,
    this.email,
    this.role,
    this.balance = 0,
    this.status = 'active',
  });

  final int id;
  final String? username;
  final String? email;
  final String? role;
  final double balance;
  final String status;

  factory Sub2User.fromJson(Map<String, dynamic> json) => Sub2User(
    id: readNumber(json['id']).toInt(),
    username: json['username']?.toString(),
    email: json['email']?.toString(),
    role: json['role']?.toString(),
    balance: readNumber(json['balance']),
    status: json['status']?.toString() ?? 'active',
  );
}

class Sub2AuthResponse {
  Sub2AuthResponse({
    required this.accessToken,
    this.refreshToken,
    required this.user,
  });

  final String accessToken;
  final String? refreshToken;
  final Sub2User user;
}

class Sub2Key {
  Sub2Key({
    required this.id,
    this.name,
    this.key,
    this.status = 'active',
    this.groupId,
    this.groupName,
    this.quota = 0,
    this.quotaUsed = 0,
    this.expiresAt,
    this.createdAt,
    this.lastUsedAt,
    this.ipWhitelist = const [],
  });

  final int id;
  final String? name;
  final String? key;
  final String status;
  final int? groupId;
  final String? groupName;
  final double quota;
  final double quotaUsed;
  final String? expiresAt;
  final String? createdAt;
  final String? lastUsedAt;
  final List<String> ipWhitelist;

  factory Sub2Key.fromJson(Map<String, dynamic> json) {
    final group = asRecord(json['group']);
    return Sub2Key(
      id: readNumber(json['id']).toInt(),
      name: json['name']?.toString(),
      key: json['key']?.toString(),
      status: json['status']?.toString() ?? 'active',
      groupId: (json['group_id'] as num?)?.toInt() ?? (group['id'] as num?)?.toInt(),
      groupName: group['name']?.toString(),
      quota: readNumber(json['quota']),
      quotaUsed: readNumber(json['quota_used']),
      expiresAt: json['expires_at']?.toString(),
      createdAt: json['created_at']?.toString(),
      lastUsedAt: json['last_used_at']?.toString(),
      ipWhitelist: ((json['ip_whitelist'] as List?) ?? [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(),
    );
  }
}

class Sub2UsageLog {
  Sub2UsageLog({
    this.id,
    this.apiKeyId,
    this.model,
    this.inputTokens,
    this.outputTokens,
    this.actualCost,
    this.totalCost,
    this.createdAt,
    this.apiKeyName,
    this.ip,
    this.group,
    this.durationMs,
    this.stream,
  });

  final int? id;
  final int? apiKeyId;
  final String? model;
  final int? inputTokens;
  final int? outputTokens;
  final double? actualCost;
  final double? totalCost;
  final String? createdAt;
  final String? apiKeyName;
  final String? ip;
  final String? group;
  final num? durationMs;
  final bool? stream;

  factory Sub2UsageLog.fromJson(Map<String, dynamic> json) => Sub2UsageLog(
    id: (json['id'] as num?)?.toInt(),
    apiKeyId: (json['api_key_id'] as num?)?.toInt(),
    model: json['model']?.toString(),
    inputTokens: (json['input_tokens'] as num?)?.toInt(),
    outputTokens: (json['output_tokens'] as num?)?.toInt(),
    actualCost: (json['actual_cost'] as num?)?.toDouble(),
    totalCost: (json['total_cost'] as num?)?.toDouble(),
    createdAt: json['created_at']?.toString(),
    apiKeyName: asRecord(json['api_key'])['name']?.toString(),
    ip: json['ip']?.toString() ?? json['client_ip']?.toString(),
    group: json['group'] is Map
        ? asRecord(json['group'])['name']?.toString()
        : json['group']?.toString(),
    durationMs: json['duration_ms'] as num? ?? json['latency_ms'] as num?,
    stream: json['stream'] == true || json['is_stream'] == true,
  );
}

class Sub2UsageStats {
  Sub2UsageStats({
    this.totalRequests,
    this.totalActualCost,
    this.rpm,
    this.tpm,
  });

  final int? totalRequests;
  final double? totalActualCost;
  final int? rpm;
  final int? tpm;

  factory Sub2UsageStats.fromJson(Map<String, dynamic> json) => Sub2UsageStats(
    totalRequests: (json['total_requests'] as num?)?.toInt(),
    totalActualCost: (json['total_actual_cost'] as num?)?.toDouble() ??
        (json['total_cost'] as num?)?.toDouble(),
    rpm: (json['rpm'] as num?)?.toInt(),
    tpm: (json['tpm'] as num?)?.toInt(),
  );
}

class Sub2DashboardStats {
  Sub2DashboardStats({
    this.totalRequests,
    this.totalActualCost,
  });

  final int? totalRequests;
  final double? totalActualCost;

  factory Sub2DashboardStats.fromJson(Map<String, dynamic> json) =>
      Sub2DashboardStats(
        totalRequests: (json['total_requests'] as num?)?.toInt(),
        totalActualCost: (json['total_actual_cost'] as num?)?.toDouble(),
      );
}

class Sub2ConnectResult {
  Sub2ConnectResult({
    required this.baseUrl,
    required this.accessToken,
    required this.refreshToken,
    required this.user,
    required this.settings,
  });

  final String baseUrl;
  final String accessToken;
  final String refreshToken;
  final Sub2User user;
  final Sub2PublicSettings settings;
}

List<T> collectSub2Items<T>(Object? data, T Function(Map<String, dynamic>) map) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((item) => map(Map<String, dynamic>.from(item)))
        .toList();
  }
  final record = asRecord(data);
  if (record['items'] is List) {
    return collectSub2Items(record['items'], map);
  }
  if (record['data'] is List) {
    return collectSub2Items(record['data'], map);
  }
  return [];
}

String friendlySub2Message(String message, [String reason = '']) {
  final text = '$reason $message'.toLowerCase();
  if (text.contains('turnstile') || reason == 'TURNSTILE_VERIFICATION_FAILED') {
    return '请先完成页面上的人机验证后再试。';
  }
  if (text.contains('already exist') ||
      text.contains('already taken') ||
      text.contains('已被注册') ||
      text.contains('已存在')) {
    return '这个邮箱已经注册过。请直接用已有账号登录，或换一个邮箱注册';
  }
  if (text.contains('invalid') &&
      (text.contains('credential') ||
          text.contains('password') ||
          text.contains('email'))) {
    return '邮箱或密码不正确';
  }
  return message.isEmpty ? '操作失败，请稍后重试' : message;
}

T unwrapSub2<T>(Map<String, dynamic> payload, String fallbackMessage) {
  final code = payload['code'];
  if (code is num && code != 0) {
    throw ApiError(
      friendlySub2Message(payload['message']?.toString() ?? fallbackMessage, payload['reason']?.toString() ?? ''),
      code.toInt(),
    );
  }
  if (payload['data'] == null) {
    throw ApiError(
      friendlySub2Message(payload['message']?.toString() ?? fallbackMessage, payload['reason']?.toString() ?? ''),
    );
  }
  return payload['data'] as T;
}

Future<T> requestSub2<T>({
  required String baseUrl,
  required String path,
  String method = 'GET',
  String? token,
  Object? data,
}) async {
  try {
    final payload = await requestJson<Map<String, dynamic>>(
      baseUrl: baseUrl,
      path: path,
      method: method,
      token: token,
      data: data,
    );
    return unwrapSub2<T>(payload, '操作失败，请稍后重试');
  } on ApiError catch (error) {
    throw ApiError(friendlySub2Message(error.message), error.status);
  }
}

Future<Sub2PublicSettings> _readPublicSettings(
  String baseUrl,
  String path,
) async {
  final payload = await requestJson<Map<String, dynamic>>(
    baseUrl: baseUrl,
    path: path,
  );
  if (_looksLikeSub2PublicSettings(payload)) {
    return Sub2PublicSettings.fromJson(payload);
  }
  if (payload['code'] is num && payload['code'] != 0) {
    throw ApiError(
      friendlySub2Message(
        payload['message']?.toString() ?? '无法读取站点设置',
        payload['reason']?.toString() ?? '',
      ),
    );
  }
  return Sub2PublicSettings.fromJson(asRecord(payload['data']));
}

Future<Sub2PublicSettings> fetchPublicSettings(String baseUrl) async {
  try {
    return await _readPublicSettings(baseUrl, '/api/v1/settings/public');
  } catch (_) {
    return _readPublicSettings(baseUrl, '/api/v1/public/settings');
  }
}

Future<Sub2User> fetchCurrentSub2User(String baseUrl, String accessToken) async =>
    Sub2User.fromJson(
      asRecord(
        await requestSub2<Object>(
          baseUrl: baseUrl,
          path: '/api/v1/auth/me',
          token: accessToken,
        ),
      ),
    );

Future<({String accessToken, String? refreshToken})> refreshSub2Token(
  String baseUrl,
  String refreshToken,
) async {
  final data = asRecord(
    await requestSub2<Object>(
      baseUrl: baseUrl,
      path: '/api/v1/auth/refresh',
      method: 'POST',
      data: {'refresh_token': refreshToken},
    ),
  );
  return (
    accessToken: data['access_token']?.toString() ?? '',
    refreshToken: data['refresh_token']?.toString(),
  );
}

Future<List<Sub2Key>> fetchSub2Keys(String baseUrl, String accessToken) async {
  final data = await requestSub2<Object>(
    baseUrl: baseUrl,
    path: '/api/v1/keys?page=1&page_size=100',
    token: accessToken,
  );
  return collectSub2Items(data, Sub2Key.fromJson);
}

Future<Sub2Key> fetchSub2KeyById(String baseUrl, String accessToken, int remoteId) async =>
    Sub2Key.fromJson(
      asRecord(
        await requestSub2<Object>(
          baseUrl: baseUrl,
          path: '/api/v1/keys/$remoteId',
          token: accessToken,
        ),
      ),
    );

Future<void> createSub2Key(
  String baseUrl,
  String accessToken,
  Map<String, dynamic> body,
) async {
  await requestSub2<Object>(
    baseUrl: baseUrl,
    path: '/api/v1/keys',
    method: 'POST',
    token: accessToken,
    data: body,
  );
}

Future<void> updateSub2Key(
  String baseUrl,
  String accessToken,
  int remoteId,
  Map<String, dynamic> body,
) async {
  await requestSub2<Object>(
    baseUrl: baseUrl,
    path: '/api/v1/keys/$remoteId',
    method: 'PUT',
    token: accessToken,
    data: body,
  );
}

Future<void> deleteSub2Key(String baseUrl, String accessToken, int remoteId) async {
  await requestSub2<Object>(
    baseUrl: baseUrl,
    path: '/api/v1/keys/$remoteId',
    method: 'DELETE',
    token: accessToken,
  );
}

Future<List<Sub2UsageLog>> fetchSub2UsageLogs(String baseUrl, String accessToken) async {
  final page = await fetchSub2UsageLogsPage(
    baseUrl,
    accessToken,
    page: 1,
    pageSize: 50,
  );
  return page.items;
}

Future<PagedItems<Sub2UsageLog>> fetchSub2UsageLogsPage(
  String baseUrl,
  String accessToken, {
  int page = 1,
  int pageSize = 20,
  String? startDate,
  String? endDate,
  String? model,
}) async {
  final query = buildQuery({
    'page': page,
    'page_size': pageSize,
    'start_date': startDate,
    'end_date': endDate,
    'model': model,
  });
  final data = await requestSub2<Object>(
    baseUrl: baseUrl,
    path: '/api/v1/usage$query',
    token: accessToken,
  );
  return parsePagedItems(
    data,
    Sub2UsageLog.fromJson,
    page: page,
    pageSize: pageSize,
  );
}

Future<Sub2UsageStats?> fetchSub2UsageStats(
  String baseUrl,
  String accessToken, {
  String? startDate,
  String? endDate,
  String? model,
}) async {
  try {
    final query = buildQuery({
      'start_date': startDate,
      'end_date': endDate,
      'model': model,
    });
    final data = await requestSub2<Object>(
      baseUrl: baseUrl,
      path: '/api/v1/usage/stats$query',
      token: accessToken,
    );
    return Sub2UsageStats.fromJson(asRecord(data));
  } catch (_) {
    return null;
  }
}

Future<Sub2DashboardStats?> fetchSub2DashboardStats(
  String baseUrl,
  String accessToken,
) async {
  try {
    return Sub2DashboardStats.fromJson(
      asRecord(
        await requestSub2<Object>(
          baseUrl: baseUrl,
          path: '/api/v1/usage/dashboard/stats',
          token: accessToken,
        ),
      ),
    );
  } catch (_) {
    return null;
  }
}

Future<List<TokenGroupOption>> fetchSub2Groups(String baseUrl, String accessToken) async {
  try {
    final groups = await requestSub2<Object>(
      baseUrl: baseUrl,
      path: '/api/v1/groups/available',
      token: accessToken,
    );
    final list = groups is List ? groups : collectSub2Items(groups, asRecord);
    return list
        .whereType<Object>()
        .map((item) => item is Map ? Map<String, dynamic>.from(item) : asRecord(item))
        .where((group) => readNumber(group['id']) > 0 && group['status'] != 'inactive')
        .map(
          (group) => TokenGroupOption(
            name: group['name']?.toString() ?? '',
            desc: (group['description']?.toString().isNotEmpty == true &&
                    group['description'].toString() != group['name']?.toString())
                ? group['description'].toString()
                : group['name']?.toString() ?? '',
            ratio: readNumber(group['rate_multiplier'], 1),
            ratioLabel: '×${readNumber(group['rate_multiplier'], 1)}',
            remoteId: readNumber(group['id']).toInt(),
          ),
        )
        .toList()
      ..sort((left, right) => left.name.compareTo(right.name));
  } catch (_) {
    return [];
  }
}

Future<Sub2ConnectResult> connectSub2Account({
  required String baseUrl,
  String? email,
  String? password,
  String? turnstileToken,
  String? accessToken,
  String? refreshToken,
}) async {
  final normalized = normalizeBaseUrl(baseUrl);
  final existingToken = accessToken?.trim() ?? '';
  if (existingToken.isNotEmpty) {
    final settings = await fetchPublicSettings(normalized);
    final user = await fetchCurrentSub2User(normalized, existingToken);
    return Sub2ConnectResult(
      baseUrl: normalized,
      accessToken: existingToken,
      refreshToken: refreshToken?.trim() ?? '',
      user: user,
      settings: settings,
    );
  }
  final loginEmail = email?.trim() ?? '';
  final loginPassword = password ?? '';
  if (loginEmail.isEmpty || loginPassword.isEmpty) {
    throw ApiError('请填写邮箱和密码');
  }
  final settings = await fetchPublicSettings(normalized);
  if (settings.turnstileEnabled && (turnstileToken == null || turnstileToken.trim().isEmpty)) {
    throw ApiError('该站点需要先完成人机验证');
  }
  final result = await requestJsonDetailed<Map<String, dynamic>>(
    baseUrl: normalized,
    path: '/api/v1/auth/login',
    method: 'POST',
    data: {
      'email': loginEmail,
      'password': loginPassword,
      if (turnstileToken != null && turnstileToken.trim().isNotEmpty)
        'turnstile_token': turnstileToken.trim(),
    },
  );
  final payload = result.data;
  if (payload['code'] is num && payload['code'] != 0) {
    throw ApiError(
      friendlySub2Message(payload['message']?.toString() ?? '登录失败', payload['reason']?.toString() ?? ''),
      result.status,
    );
  }
  final data = asRecord(payload['data']);
  if (data.isEmpty) {
    throw ApiError(
      friendlySub2Message(payload['message']?.toString() ?? '登录失败', payload['reason']?.toString() ?? ''),
      result.status,
    );
  }
  if (data['requires_2fa'] == true) {
    throw ApiError('该账号开启了两步验证。钥仓暂不支持，请先在站点关闭后再连。');
  }
  final token = data['access_token']?.toString() ?? '';
  var user = asRecord(data['user']).isEmpty ? null : Sub2User.fromJson(asRecord(data['user']));
  user ??= await fetchCurrentSub2User(normalized, token);
  return Sub2ConnectResult(
    baseUrl: normalized,
    accessToken: token,
    refreshToken: data['refresh_token']?.toString() ?? '',
    user: user,
    settings: settings,
  );
}

class Sub2RegisterOutcome {
  const Sub2RegisterOutcome({
    required this.accessToken,
    required this.refreshToken,
    this.user,
  });

  final String accessToken;
  final String refreshToken;
  final Sub2User? user;
}

String describeSub2RegisterError(String message, [String reason = '']) {
  final text = '$reason $message';
  final lower = text.toLowerCase();
  if (lower.contains('turnstile') || reason == 'TURNSTILE_VERIFICATION_FAILED') {
    return '人机验证未通过，请重试';
  }
  if (RegExp(r'already exists|already taken|已被注册|已存在|已被占用').hasMatch(lower)) {
    return '这个邮箱已经注册过，请直接用已有账号登录';
  }
  if (lower.contains('verify_code') || lower.contains('verification') || lower.contains('验证码')) {
    return '验证码不正确或已过期';
  }
  if (lower.contains('suffix') || lower.contains('not allowed') || lower.contains('不允许')) {
    return '站点不允许这个邮箱后缀注册';
  }
  if (lower.contains('register') && (lower.contains('disabled') || lower.contains('closed'))) {
    return '该站点已关闭注册';
  }
  if (lower.contains('password')) {
    return '密码不符合站点要求，请重试';
  }
  if (lower.contains('email')) {
    return '邮箱无效或站点不接受这个邮箱';
  }
  final trimmed = text.trim();
  return trimmed.isEmpty ? '注册失败，请稍后重试' : trimmed;
}

Future<void> sendSub2VerifyCode({
  required String baseUrl,
  required String email,
  String? turnstileToken,
}) async {
  final payload = await requestJsonDetailed<Map<String, dynamic>>(
    baseUrl: normalizeBaseUrl(baseUrl),
    path: '/api/v1/auth/send-verify-code',
    method: 'POST',
    data: {
      'email': email.trim(),
      if (turnstileToken != null && turnstileToken.trim().isNotEmpty)
        'turnstile_token': turnstileToken.trim(),
    },
  );
  final record = payload.data;
  final code = record['code'];
  if (code is num && code != 0) {
    throw ApiError(
      friendlySub2Message(
        record['message']?.toString() ?? '发送验证码失败',
        record['reason']?.toString() ?? '',
      ),
      payload.status,
    );
  }
}

Future<Sub2RegisterOutcome> registerSub2Account({
  required String baseUrl,
  required String email,
  required String password,
  String? verifyCode,
  String? turnstileToken,
}) async {
  Map<String, dynamic> record;
  int status;
  try {
    final payload = await requestJsonDetailed<Map<String, dynamic>>(
      baseUrl: normalizeBaseUrl(baseUrl),
      path: '/api/v1/auth/register',
      method: 'POST',
      data: {
        'email': email.trim(),
        'password': password,
        if (verifyCode != null && verifyCode.trim().isNotEmpty)
          'verify_code': verifyCode.trim(),
        if (turnstileToken != null && turnstileToken.trim().isNotEmpty)
          'turnstile_token': turnstileToken.trim(),
      },
    );
    record = payload.data;
    status = payload.status;
  } on ApiError catch (error) {
    throw ApiError(describeSub2RegisterError(error.message), error.status);
  }
  final code = record['code'];
  if (code is num && code != 0) {
    throw ApiError(
      describeSub2RegisterError(
        record['message']?.toString() ?? '注册失败',
        record['reason']?.toString() ?? '',
      ),
      status,
    );
  }
  final data = asRecord(record['data']);
  final token = (data['access_token'] ?? '').toString().trim();
  if (data.isEmpty || token.isEmpty) {
    throw ApiError('站点没有返回登录凭证，注册可能未完成，请稍后用邮箱密码登录');
  }
  final userRecord = asRecord(data['user']);
  return Sub2RegisterOutcome(
    accessToken: token,
    refreshToken: data['refresh_token']?.toString() ?? '',
    user: userRecord.isEmpty ? null : Sub2User.fromJson(userRecord),
  );
}
