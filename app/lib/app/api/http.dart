import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:socks5_proxy/socks_client.dart';
import 'package:vault/app/debug/http_request_log.dart';
import 'package:vault/app/models/domain.dart';

const _proxyZoneKey = #yuconNetworkProxy;
const _cookieZoneKey = #yuconRequestCookies;
const _proxyChannel = MethodChannel('cc.yucon.vault/proxy');
const kHttpUserAgent =
    'Mozilla/5.0 (Linux; Android 14; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36';

HttpClient _newHttpClient() {
  final io = HttpClient();
  io.userAgent = kHttpUserAgent;
  io.autoUncompress = true;
  return io;
}

final _directClient = IOClient(_newHttpClient());
final _clients = <String, http.Client>{};
final _pendingClients = <String, Future<http.Client>>{};

class ApiError implements Exception {
  ApiError(this.message, [this.status]);

  final String message;
  final int? status;

  @override
  String toString() => message;
}

const kSiteNetworkBlockedMessage =
    '这个网站不支持在当前网络下访问。不是账号填错，是站点不允许你现在所用的网络打开它。请到「我的」换一个可用代理后再连';

const kSiteUnreachableMessage = '手机是有网的，但这个网站当前打不开。不是登录过期。可到「我的」换一个可用代理后再同步';

const kDnsPollutedMessage =
    '当前网络的域名解析不正常，这个网站可能被 DNS 污染了。不是登录过期。请到「我的」换一个可用代理后再同步';

bool looksLikeNetworkBlockPage(String text) {
  final lower = text.toLowerCase();
  return RegExp(
    r'sorry,\s*you have been blocked|'
    r'you are unable to access|'
    r'why have i been blocked|'
    r'blocked_why|'
    r'cf-screenshot-full|'
    r'error 1020|'
    r'error code[:\s]+1020|'
    r'cf-error-code[^0-9]{0,12}1020|'
    r'access denied\s*\|',
  ).hasMatch(lower);
}

bool looksLikeNetworkBlockMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed == kSiteNetworkBlockedMessage) {
    return true;
  }
  if (looksLikeNetworkBlockPage(trimmed)) {
    return true;
  }
  if (trimmed == kSiteUnreachableMessage) {
    return true;
  }
  return RegExp(
    r'不支持在当前网络|不支持当前网络|站点开了访问防护|当前直连过不去|不允许你现在所用的网络|当前网络连不上这个网站|这个网站当前打不开|手机是有网的',
  ).hasMatch(trimmed);
}

bool looksLikeDnsPollutedMessage(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return false;
  }
  if (trimmed == kDnsPollutedMessage) {
    return true;
  }
  return RegExp(r'域名解析不正常|DNS 污染|dns污染|解析到了错误地址').hasMatch(trimmed);
}

bool isDnsPollutedError(Object error) {
  if (error is ApiError) {
    return looksLikeDnsPollutedMessage(error.message);
  }
  return looksLikeDnsPollutedMessage(error.toString());
}

bool isNetworkBlockedError(Object error) {
  if (error is ApiError) {
    if (looksLikeNetworkBlockMessage(error.message)) {
      return true;
    }
    if (error.status == 403 &&
        !RegExp(
          r'未登录|登录过期|凭证无效|unauthor|token.*(expir|invalid)',
          caseSensitive: false,
        ).hasMatch(error.message) &&
        _looksLikeHtmlOrCloudflare(error.message)) {
      return true;
    }
    return false;
  }
  return looksLikeNetworkBlockMessage(error.toString());
}

bool _looksLikeHtmlOrCloudflare(String text) {
  final trimmed = text.trimLeft();
  if (trimmed.isEmpty) {
    return false;
  }
  final lower = trimmed.toLowerCase();
  return trimmed.startsWith('<') ||
      lower.contains('<!doctype') ||
      lower.contains('<html') ||
      lower.contains('cloudflare ray id') ||
      lower.contains('cf-error') ||
      lower.contains('cf-wrapper') ||
      lower.contains('5xx-error-landing') ||
      lower.contains('just a moment') ||
      lower.contains('attention required') ||
      lower.contains('challenge-platform') ||
      looksLikeNetworkBlockPage(trimmed);
}

String sanitizeErrorText(String text, [String fallback = '站点暂时无法响应，请稍后重试']) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return fallback;
  }
  final lower = trimmed.toLowerCase();
  if (_looksLikeHtmlOrCloudflare(trimmed)) {
    if (RegExp(r'error 521|web server is down').hasMatch(lower)) {
      return '站点服务器没开。请先在浏览器打开同一个地址，能打开再回来连接';
    }
    if (RegExp(r'error 522|connection timed out').hasMatch(lower)) {
      return '站点响应超时。请先在浏览器打开同一个地址，或稍后再试';
    }
    if (RegExp(r'error 523|origin is unreachable').hasMatch(lower)) {
      return '连不上这个站点的服务器，请稍后再试';
    }
    if (RegExp(r'error 524|a timeout occurred').hasMatch(lower)) {
      return '站点处理超时，请稍后再试';
    }
    if (RegExp(
      r'error 525|error 526|ssl handshake failed|invalid ssl certificate',
    ).hasMatch(lower)) {
      return '站点证书有问题，请检查地址是否为 https';
    }
    if (looksLikeNetworkBlockPage(trimmed)) {
      return kSiteNetworkBlockedMessage;
    }
    if (RegExp(r'未备案|域名不存在|上网助手|该网站无法访问|网站无法访问|dns.?poison|nxdomain')
            .hasMatch(lower) &&
        !looksLikeNetworkBlockPage(trimmed)) {
      return kDnsPollutedMessage;
    }
    if (RegExp(r'5xx-error-landing|cf-error-footer|error 50[0-4]|error 52[0-6]')
            .hasMatch(lower) &&
        !looksLikeNetworkBlockPage(trimmed)) {
      return '站点暂时不可用。请先在浏览器打开同一个地址，能打开再回来连接';
    }
    if (RegExp(
      r'just a moment|cf-browser-verification|challenge-platform|cf-chl-|enable javascript and cookies to continue',
    ).hasMatch(lower)) {
      return '账号没填错。站点开了访问防护，当前直连过不去。到「我的」填好可用代理后再连';
    }
    if (RegExp(r'attention required').hasMatch(lower)) {
      return '账号没填错。站点开了访问防护，当前直连过不去。到「我的」填好可用代理后再连';
    }
    return '站点暂时不可用。请先在浏览器打开同一个地址，能打开再回来连接';
  }
  if (trimmed.length > 160 ||
      (trimmed.contains('<') && trimmed.contains('>'))) {
    return fallback;
  }
  if (RegExp(
    r'^(forbidden|access denied)\.?$',
    caseSensitive: false,
  ).hasMatch(trimmed)) {
    return kSiteNetworkBlockedMessage;
  }
  if (trimmed.contains('连接超时') ||
      (RegExp(r'timed?\s*out', caseSensitive: false).hasMatch(trimmed) &&
          trimmed.length < 80)) {
    return kSiteUnreachableMessage;
  }
  return trimmed;
}

String userFacingError(Object error, [String fallback = '操作失败，请稍后重试']) {
  if (error is ApiError) {
    return sanitizeErrorText(error.message, fallback);
  }
  var text = error.toString().trim();
  text = text.replaceFirst(RegExp(r'^(Exception|Error|ApiError):\s*'), '');
  if (text.isEmpty) {
    return fallback;
  }
  final lower = text.toLowerCase();
  if (lower.contains('异常解析地址')) {
    return kDnsPollutedMessage;
  }
  if (lower.contains('failed host lookup') ||
      lower.contains('name or service not known') ||
      lower.contains('nodename nor servname') ||
      lower.contains('no address associated')) {
    return '找不到这个站点。如果地址没错，多半是当前网络的域名解析不正常';
  }
  if (lower.contains('certificate_verify_failed') ||
      lower.contains('hostname mismatch') ||
      (lower.contains('handshakeexception') && lower.contains('certificate'))) {
    return kDnsPollutedMessage;
  }
  if (lower.contains('connection refused') ||
      lower.contains('network is unreachable') ||
      lower.contains('connection reset') ||
      lower.contains('software caused connection abort') ||
      lower.contains('proxy tunnel failed') ||
      lower.contains('proxy failed')) {
    final proxy = currentRequestProxy();
    if (proxy != null && proxy.isConfigured) {
      return '代理连不上。请确认 ${proxy.addressText} 已开启后再试';
    }
    return '连不上这个站点，请稍后重试';
  }
  if (lower.contains('socketexception') ||
      lower.contains('clientexception') ||
      lower.contains('handshakeexception') ||
      lower.contains('certificate')) {
    return '网络连接失败，请检查网络后重试';
  }
  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('超时')) {
    return kSiteUnreachableMessage;
  }
  if (RegExp(r'(null check operator|type \x27|rangeerror|#0 |dart:)')
          .hasMatch(lower) ||
      text.contains('RangeError') ||
      text.contains('Null check')) {
    return fallback;
  }
  return sanitizeErrorText(text, fallback);
}

bool isAuthExpiredError(Object error) {
  if (isNetworkBlockedError(error) || isDnsPollutedError(error)) {
    return false;
  }
  if (error is! ApiError) {
    return false;
  }
  final text = error.message.toLowerCase();
  final looksAuth = RegExp(
    r'unauthor|unauthenticated|token.*(expir|invalid)|jwt.*(expir|invalid)|登录过期|未登录|凭证无效|invalid access token|access token 无效',
  ).hasMatch(text);
  if (error.status == 401) {
    return looksAuth || !_looksLikeHtmlOrCloudflare(error.message);
  }
  return looksAuth;
}

class RequestResult<T> {
  RequestResult({
    required this.data,
    required this.cookies,
    required this.status,
  });

  final T data;
  final String cookies;
  final int status;
}

const cookieAuthPrefix = 'cookie:';
const nativeCookieAuth = 'cookie:native';
const _yuconCookiesField = '__yucon_cookies';

String normalizeBaseUrl(String value) {
  final trimmed = value.trim().replaceFirst(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) {
    throw ApiError('请填写站点地址');
  }
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(trimmed)) {
    return trimmed;
  }
  return 'https://$trimmed';
}

String joinUrl(String baseUrl, String path) {
  final normalizedPath = path.startsWith('/') ? path : '/$path';
  return '${normalizeBaseUrl(baseUrl)}$normalizedPath';
}

String sanitizeHeaderValue(String value) =>
    value.replaceAll(RegExp(r'[\r\n]+'), '').trim();

Map<String, dynamic> asRecord(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return <String, dynamic>{};
}

double readNumber(Object? value, [double fallback = 0]) {
  if (value is num) {
    return value.toDouble();
  }
  return num.tryParse(value?.toString() ?? '')?.toDouble() ?? fallback;
}

String buildQuery(Map<String, Object?> params) {
  final parts = <String>[];
  for (final entry in params.entries) {
    final value = entry.value;
    if (value == null) {
      continue;
    }
    if (value is String && value.trim().isEmpty) {
      continue;
    }
    parts.add(
      '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent('$value')}',
    );
  }
  return parts.isEmpty ? '' : '?${parts.join('&')}';
}

class PagedItems<T> {
  const PagedItems({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
    this.totalKnown = true,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  final bool totalKnown;
}

List<Map<String, dynamic>> collectMaps(Object? data) {
  if (data is List) {
    return data
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
  final record = asRecord(data);
  if (record['items'] is List) {
    return collectMaps(record['items']);
  }
  if (record['data'] is List) {
    return collectMaps(record['data']);
  }
  if (record['logs'] is List) {
    return collectMaps(record['logs']);
  }
  if (record['records'] is List) {
    return collectMaps(record['records']);
  }
  return [];
}

int? _readPositiveInt(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = readNumber(value).round();
  return parsed < 0 ? null : parsed;
}

PagedItems<T> parsePagedItems<T>(
  Object? data,
  T Function(Map<String, dynamic>) map, {
  int page = 1,
  int pageSize = 20,
}) {
  final items = collectMaps(data).map(map).toList();
  if (data is List) {
    return PagedItems(
      items: items,
      total: items.length,
      page: page,
      pageSize: pageSize,
      totalKnown: false,
    );
  }
  final record = asRecord(data);
  final nested = asRecord(record['pagination']);
  final meta = asRecord(record['meta']);
  final source = nested.isNotEmpty ? nested : (meta.isNotEmpty ? meta : record);
  final parsedPage =
      _readPositiveInt(
        source['page'] ?? source['current_page'] ?? source['p'],
      ) ??
      page;
  final parsedSize =
      _readPositiveInt(
        source['page_size'] ??
            source['pageSize'] ??
            source['per_page'] ??
            source['limit'],
      ) ??
      pageSize;
  final totalValue =
      source['total'] ??
      source['total_count'] ??
      source['count'] ??
      record['total'];
  final hasTotal = totalValue != null;
  return PagedItems(
    items: items,
    total: hasTotal ? readNumber(totalValue).round() : items.length,
    page: parsedPage == 0 ? 1 : parsedPage,
    pageSize: parsedSize == 0 ? pageSize : parsedSize,
    totalKnown: hasTotal,
  );
}

PagedItems<T> parsePagedItemsFromPayload<T>(
  Map<String, dynamic> payload,
  T Function(Map<String, dynamic>) map, {
  int page = 1,
  int pageSize = 20,
}) {
  final data = payload['data'];
  if (data is List) {
    final items = collectMaps(data).map(map).toList();
    final totalValue = payload['total'];
    return PagedItems(
      items: items,
      total: totalValue != null ? readNumber(totalValue).round() : items.length,
      page: page,
      pageSize: pageSize,
      totalKnown: totalValue != null,
    );
  }
  return parsePagedItems(data, map, page: page, pageSize: pageSize);
}

String messageFromPayload(Object? payload, String fallback) {
  final record = asRecord(payload);
  var message = (record['message']?.toString() ?? '').trim();
  if (message.isEmpty) {
    final error = record['error'];
    if (error is Map) {
      message = (error['message']?.toString() ?? '').trim();
    } else if (error is String) {
      message = error.trim();
    }
  }
  if (message.isEmpty) {
    return fallback;
  }
  if (message.contains('New-Api-User')) {
    return '该站点还需要填写用户 ID。请打开站点「个人设置」查看数字 ID，并和访问令牌一起填。';
  }
  if (message.contains('access token 无效') ||
      message.toLowerCase().contains('invalid access token')) {
    return '访问令牌无效。请重新生成，不要填写 sk- 开头的密钥。';
  }
  final reason = record['reason']?.toString() ?? '';
  if (reason == 'TURNSTILE_VERIFICATION_FAILED' ||
      message.toLowerCase().contains('turnstile')) {
    return '请先完成页面上的人机验证后再试。';
  }
  return message;
}

const _cookieAttributeNames = {
  'path',
  'domain',
  'expires',
  'max-age',
  'secure',
  'httponly',
  'samesite',
  'partitioned',
  'priority',
};

String cookiePair(String setCookie) {
  final pair = setCookie.split(';').first.trim();
  if (!pair.contains('=')) {
    return '';
  }
  final attributes = setCookie.toLowerCase();
  if (attributes.contains('max-age=0') || attributes.contains('max-age=-')) {
    return '';
  }
  return pair;
}

void _putCookiePair(Map<String, String> map, String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || !trimmed.contains('=')) {
    return;
  }
  final eq = trimmed.indexOf('=');
  final name = trimmed.substring(0, eq).trim();
  final value = trimmed.substring(eq + 1);
  if (name.isEmpty || _cookieAttributeNames.contains(name.toLowerCase())) {
    return;
  }
  map[name] = value;
}

String mergeCookies(Iterable<String> chunks) {
  final map = <String, String>{};
  for (final chunk in chunks) {
    final trimmed = chunk.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final pieces = trimmed.contains('|||') ? trimmed.split('|||') : [trimmed];
    for (final piece in pieces) {
      final item = piece.trim();
      if (item.isEmpty) {
        continue;
      }
      if (item.contains(';')) {
        for (final part in item.split(';')) {
          _putCookiePair(map, part);
        }
        continue;
      }
      var pair = cookiePair(item);
      if (pair.isEmpty && item.contains('=')) {
        pair = item;
      }
      _putCookiePair(map, pair);
    }
  }
  return map.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
}

String asCookieAuth(String cookieHeader) => '$cookieAuthPrefix$cookieHeader';

Object? parsePayload(Object? payload) {
  if (payload is! String) {
    return payload;
  }
  try {
    return jsonDecode(payload);
  } catch (_) {
    return payload;
  }
}

({Object? data, String cookies}) takeSidecarCookies(Object? payload) {
  if (payload is! Map) {
    return (data: payload, cookies: '');
  }
  final record = Map<String, dynamic>.from(payload);
  final cookies = record[_yuconCookiesField] is String
      ? record[_yuconCookiesField] as String
      : '';
  record.remove(_yuconCookiesField);
  return (data: record, cookies: cookies);
}

void applyAuthHeaders(
  Map<String, String> header,
  String? token,
  String? cookie,
) {
  final cookieHeader = cookie?.trim().isNotEmpty == true
      ? cookie!.trim()
      : (token != null &&
                token.startsWith(cookieAuthPrefix) &&
                token != nativeCookieAuth
            ? token.substring(cookieAuthPrefix.length)
            : '');
  if (cookieHeader.isNotEmpty) {
    header['Cookie'] = sanitizeHeaderValue(cookieHeader);
  }
  if (token != null &&
      token.isNotEmpty &&
      !token.startsWith(cookieAuthPrefix)) {
    header['Authorization'] = 'Bearer ${sanitizeHeaderValue(token)}';
  }
}

NetworkProxy? currentRequestProxy() {
  final value = Zone.current[_proxyZoneKey];
  return value is NetworkProxy ? value : null;
}

String? currentRequestCookies() {
  final value = Zone.current[_cookieZoneKey];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

Future<T> runWithProxy<T>(
  NetworkProxy? proxy,
  Future<T> Function() body, {
  String? cookies,
}) {
  final values = <Object?, Object?>{};
  if (proxy != null && proxy.isConfigured) {
    values[_proxyZoneKey] = proxy;
  }
  if (cookies != null && cookies.trim().isNotEmpty) {
    values[_cookieZoneKey] = cookies.trim();
  }
  if (values.isEmpty) {
    return body();
  }
  return runZoned(body, zoneValues: values);
}

http.Client _directHttpClient() => _directClient;

Map<String, String> _apiHeaders(String baseUrl) {
  final origin = normalizeBaseUrl(baseUrl);
  return {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
    'User-Agent': kHttpUserAgent,
    'Origin': origin,
    'Referer': '$origin/',
  };
}

Future<InternetAddress> _resolveProxyHost(String host) async {
  final parsed = InternetAddress.tryParse(host.trim());
  if (parsed != null) {
    return parsed;
  }
  final lookedUp = await InternetAddress.lookup(host.trim());
  if (lookedUp.isEmpty) {
    throw ApiError('找不到代理地址 $host');
  }
  return lookedUp.first;
}

Future<void> _configureHttpClient(HttpClient io, NetworkProxy proxy) async {
  if (proxy.type == NetworkProxyType.socks5) {
    final address = await _resolveProxyHost(proxy.host);
    SocksTCPClient.assignToHttpClient(io, [
      ProxySettings(
        address,
        proxy.port,
        username: proxy.hasAuth ? proxy.username : null,
        password: proxy.hasAuth ? proxy.password : null,
      ),
    ]);
    return;
  }
  io.findProxy = (_) => proxy.pacDirective;
  if (proxy.hasAuth) {
    io.authenticateProxy = (host, port, scheme, realm) async {
      io.addProxyCredentials(
        proxy.host,
        proxy.port,
        realm ?? '',
        HttpClientBasicCredentials(proxy.username, proxy.password),
      );
      return true;
    };
  }
}

Future<http.Client> _clientFor(NetworkProxy? proxy) async {
  if (proxy == null || !proxy.isConfigured) {
    return _directHttpClient();
  }
  final cached = _clients[proxy.cacheKey];
  if (cached != null) {
    return cached;
  }
  return _pendingClients.putIfAbsent(proxy.cacheKey, () async {
    try {
      final io = _newHttpClient();
      await _configureHttpClient(io, proxy);
      final client = IOClient(io);
      _clients[proxy.cacheKey] = client;
      return client;
    } finally {
      _pendingClients.remove(proxy.cacheKey);
    }
  });
}

List<String> cookieUrlsForSite(String baseUrl) {
  final origin = normalizeBaseUrl(baseUrl);
  return [
    origin,
    '$origin/',
    '$origin/api/user/auth',
    '$origin/api/user/auth/',
    '$origin/api/user/auth/refresh',
    '$origin/dashboard',
    '$origin/dashboard/',
    '$origin/sign-in',
    '$origin/login',
  ];
}

Future<String> readWebViewCookieHeader(String url) async {
  final candidates = <String>{};
  final trimmed = url.trim();
  if (trimmed.isNotEmpty) {
    candidates.add(trimmed);
  }
  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && parsed.host.isNotEmpty) {
    final origin = parsed.hasPort
        ? '${parsed.scheme}://${parsed.host}:${parsed.port}'
        : '${parsed.scheme}://${parsed.host}';
    candidates.add(origin);
    candidates.add('$origin/');
    if (parsed.scheme == 'https') {
      candidates.add('http://${parsed.host}/');
    }
    candidates.addAll(cookieUrlsForSite(origin));
  }
  final collected = <String>[];
  for (final candidate in candidates) {
    try {
      final raw = await _proxyChannel.invokeMethod<String>('getCookies', {
        'url': candidate,
      });
      if (raw != null && raw.trim().isNotEmpty) {
        collected.add(raw.trim());
      }
    } catch (_) {}
  }
  return mergeCookies(collected);
}

Future<String> readSiteCookieHeader(String baseUrl) async {
  try {
    return await readWebViewCookieHeader(normalizeBaseUrl(baseUrl));
  } catch (_) {
    return '';
  }
}

Future<void> applyWebViewProxy(NetworkProxy? proxy) async {
  try {
    if (proxy != null && proxy.isConfigured) {
      await _proxyChannel.invokeMethod<void>('setWebViewProxy', {
        'host': proxy.host,
        'port': proxy.port,
        'scheme': switch (proxy.type) {
          NetworkProxyType.socks5 => 'socks5',
          NetworkProxyType.https => 'https',
          NetworkProxyType.http => 'http',
        },
        'socks': proxy.type == NetworkProxyType.socks5,
      });
      return;
    }
    await _proxyChannel.invokeMethod<void>('clearWebViewProxy');
  } catch (_) {}
}

Future<void> testNetworkProxy(NetworkProxy proxy, {String? probeUrl}) async {
  if (!proxy.isConfigured) {
    throw ApiError('请填写主机地址和端口');
  }
  var probe = probeUrl?.trim() ?? '';
  if (probe.isEmpty) {
    probe = 'https://www.gstatic.com/generate_204';
  } else if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(probe)) {
    probe = 'https://$probe';
  }
  final io = _newHttpClient();
  IOClient? client;
  final started = DateTime.now();
  try {
    await _configureHttpClient(io, proxy);
    client = IOClient(io);
    final request = http.Request('GET', Uri.parse(probe));
    request.headers['User-Agent'] = kHttpUserAgent;
    request.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
    final streamed = await client
        .send(request)
        .timeout(const Duration(seconds: 8));
    await streamed.stream.drain();
    _logHttp(
      method: 'GET',
      url: probe,
      duration: DateTime.now().difference(started),
      requestHeaders: request.headers,
      status: streamed.statusCode,
      responseHeaders: streamed.headers,
    );
    if (streamed.statusCode >= 500) {
      throw ApiError('代理已连上，但测试站点没有响应');
    }
  } on TimeoutException {
    _logHttp(
      method: 'GET',
      url: probe,
      duration: DateTime.now().difference(started),
      error: '代理连接超时',
    );
    throw ApiError('代理连接超时，请确认地址和端口');
  } catch (error) {
    if (error is! ApiError) {
      _logHttp(
        method: 'GET',
        url: probe,
        duration: DateTime.now().difference(started),
        error: error.toString(),
      );
      throw ApiError(userFacingError(error, '代理连不上，请检查地址、端口和类型'));
    }
    rethrow;
  } finally {
    if (client != null) {
      client.close();
    } else {
      io.close(force: true);
    }
  }
}

Future<HttpClient> createProxiedHttpClient() async {
  final io = _newHttpClient();
  final proxy = currentRequestProxy();
  if (proxy != null && proxy.isConfigured) {
    await _configureHttpClient(io, proxy);
  }
  return io;
}

Future<({int status, String url})> probeHttpNavigation(
  String url, {
  String? cookie,
  Duration timeout = const Duration(seconds: 12),
}) async {
  final client = await _clientFor(currentRequestProxy());
  final request = http.Request('GET', Uri.parse(url));
  request.followRedirects = true;
  request.maxRedirects = 8;
  request.headers['User-Agent'] = kHttpUserAgent;
  request.headers['Accept'] =
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
  request.headers['Accept-Language'] = 'zh-CN,zh;q=0.9,en;q=0.8';
  final cookieHeader = (cookie ?? '').trim();
  if (cookieHeader.isNotEmpty) {
    request.headers['Cookie'] = sanitizeHeaderValue(cookieHeader);
  }
  final streamed = await client.send(request).timeout(timeout);
  await streamed.stream.drain();
  return (
    status: streamed.statusCode,
    url: streamed.request?.url.toString() ?? url,
  );
}

Future<RequestResult<T>> requestJsonDetailed<T>({
  String method = 'GET',
  required String path,
  required String baseUrl,
  String? token,
  String? userId,
  String? cookie,
  Object? data,
  Duration timeout = const Duration(seconds: 20),
  bool requireJson = true,
  bool throwOnHttpError = true,
  Map<String, String>? headers,
}) async {
  final url = Uri.parse(joinUrl(baseUrl, path));
  final header = _apiHeaders(baseUrl);
  if (data != null && method != 'GET') {
    header['Content-Type'] = 'application/json';
  }
  applyAuthHeaders(
    header,
    token,
    mergeCookies([currentRequestCookies() ?? '', cookie ?? '']),
  );
  if (headers != null) {
    headers.forEach((key, value) {
      final sanitized = sanitizeHeaderValue(value);
      if (sanitized.isEmpty) {
        header.remove(key);
      } else {
        header[key] = sanitized;
      }
    });
  }
  if (userId != null && userId.isNotEmpty) {
    header['New-Api-User'] = sanitizeHeaderValue(userId);
  }

  final started = DateTime.now();
  String? requestBody;
  if (data != null && method != 'GET') {
    requestBody = jsonEncode(data);
  }

  Future<http.Response> sendOnce(http.Client client) async {
    final request = http.Request(method, url);
    request.headers.addAll(header);
    final body = requestBody;
    if (body != null) {
      request.body = body;
    }
    final streamed = await client.send(request).timeout(timeout);
    return http.Response.fromStream(streamed);
  }

  http.Response response;
  try {
    response = await sendOnce(await _clientFor(currentRequestProxy()));
    _logHttp(
      method: method,
      url: url.toString(),
      duration: DateTime.now().difference(started),
      requestHeaders: header,
      requestBody: requestBody,
      status: response.statusCode,
      responseHeaders: response.headers,
      responseBody: response.body,
    );
  } on TimeoutException {
    _logHttp(
      method: method,
      url: url.toString(),
      duration: DateTime.now().difference(started),
      requestHeaders: header,
      requestBody: requestBody,
      error: '连接超时',
    );
    final proxy = currentRequestProxy();
    throw ApiError(
      proxy != null && proxy.isConfigured
          ? '代理连不上。请确认 ${proxy.addressText} 已开启后再试'
          : kSiteUnreachableMessage,
    );
  } catch (error) {
    _logHttp(
      method: method,
      url: url.toString(),
      duration: DateTime.now().difference(started),
      requestHeaders: header,
      requestBody: requestBody,
      error: error.toString(),
    );
    throw ApiError(userFacingError(error, '网络请求失败'));
  }

  final status = response.statusCode;
  final parsed = parsePayload(
    response.body.isEmpty ? <String, dynamic>{} : response.body,
  );
  final sidecar = takeSidecarCookies(parsed);
  final setCookies = <String>[];
  final split = response.headersSplitValues['set-cookie'];
  if (split != null) {
    setCookies.addAll(split);
  } else if (response.headers['set-cookie'] != null) {
    setCookies.add(response.headers['set-cookie']!);
  }
  final cookies = mergeCookies([...setCookies, sidecar.cookies]);

  if (status == 204) {
    return RequestResult(
      data: <String, dynamic>{} as T,
      cookies: cookies,
      status: status,
    );
  }
  if (status >= 400) {
    if (!throwOnHttpError && sidecar.data is Map) {
      return RequestResult(
        data: sidecar.data as T,
        cookies: cookies,
        status: status,
      );
    }
    final fromPayload = sidecar.data is String
        ? sanitizeErrorText(sidecar.data as String, '')
        : messageFromPayload(sidecar.data, '');
    final raw = fromPayload.isNotEmpty ? fromPayload : response.body;
    throw ApiError(sanitizeErrorText(raw, '站点暂时无法响应，请稍后重试'), status);
  }
  if (sidecar.data is String) {
    if (!requireJson) {
      return RequestResult(
        data: <String, dynamic>{'raw': sidecar.data} as T,
        cookies: cookies,
        status: status,
      );
    }
    throw ApiError(sanitizeErrorText(sidecar.data as String), status);
  }
  return RequestResult(
    data: (sidecar.data ?? <String, dynamic>{}) as T,
    cookies: cookies,
    status: status,
  );
}

Future<T> requestJson<T>({
  String method = 'GET',
  required String path,
  required String baseUrl,
  String? token,
  String? userId,
  String? cookie,
  Object? data,
  Duration timeout = const Duration(seconds: 20),
  bool requireJson = true,
  bool throwOnHttpError = true,
  Map<String, String>? headers,
}) async {
  final result = await requestJsonDetailed<T>(
    method: method,
    path: path,
    baseUrl: baseUrl,
    token: token,
    userId: userId,
    cookie: cookie,
    data: data,
    timeout: timeout,
    requireJson: requireJson,
    throwOnHttpError: throwOnHttpError,
    headers: headers,
  );
  return result.data;
}

Future<Uint8List> requestBytes({
  required String url,
  String? token,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final uri = Uri.parse(url);
  final header = <String, String>{
    'Accept': 'image/*,application/octet-stream,*/*',
    'User-Agent': kHttpUserAgent,
  };
  applyAuthHeaders(
    header,
    token,
    mergeCookies([currentRequestCookies() ?? '']),
  );
  final started = DateTime.now();
  try {
    final response = await (await _clientFor(currentRequestProxy()))
        .get(uri, headers: header)
        .timeout(timeout);
    _logHttp(
      method: 'GET',
      url: url,
      duration: DateTime.now().difference(started),
      requestHeaders: header,
      status: response.statusCode,
      responseHeaders: response.headers,
      responseBody: '[binary ${response.bodyBytes.length} bytes]',
    );
    if (response.statusCode >= 400) {
      throw ApiError('图像地址无法下载', response.statusCode);
    }
    if (response.bodyBytes.isEmpty) {
      throw ApiError('图像地址是空的');
    }
    return response.bodyBytes;
  } on ApiError {
    rethrow;
  } on TimeoutException {
    _logHttp(
      method: 'GET',
      url: url,
      duration: DateTime.now().difference(started),
      requestHeaders: header,
      error: '连接超时',
    );
    throw ApiError('图像下载超时');
  } catch (error) {
    _logHttp(
      method: 'GET',
      url: url,
      duration: DateTime.now().difference(started),
      requestHeaders: header,
      error: error.toString(),
    );
    throw ApiError(userFacingError(error, '图像下载失败'));
  }
}

void logRawHttpRequest({
  required String method,
  required String url,
  required Duration duration,
  Map<String, String>? requestHeaders,
  int? status,
  String? responseBody,
  String? error,
}) {
  _logHttp(
    method: method,
    url: url,
    duration: duration,
    requestHeaders: requestHeaders,
    status: status,
    responseBody: responseBody,
    error: error,
  );
}

void _logHttp({
  required String method,
  required String url,
  required Duration duration,
  Map<String, String>? requestHeaders,
  String? requestBody,
  int? status,
  Map<String, String>? responseHeaders,
  String? responseBody,
  String? error,
}) {
  if (kDebugMode) {
    final previewSource = (error ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = previewSource.length > 120
        ? previewSource.substring(0, 120)
        : previewSource;
    debugPrint(
      '[YUCON_HTTP] $method ${status ?? 'ERR'} $url ${duration.inMilliseconds}ms ${preview.isEmpty ? '' : preview}',
    );
  }
  try {
    HttpRequestLogger.instance.capture(
      method: method,
      url: url,
      duration: duration,
      requestHeaders: requestHeaders,
      requestBody: requestBody,
      status: status,
      responseHeaders: responseHeaders,
      responseBody: responseBody,
      error: error,
    );
  } catch (_) {}
}
