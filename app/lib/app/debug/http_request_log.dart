import 'dart:convert';

import 'package:flutter/foundation.dart';

const _maxBodyChars = 12000;
const _maxRecords = 500;

const _sensitiveHeaderNames = {
  'authorization',
  'cookie',
  'set-cookie',
  'new-api-user',
  'x-api-key',
  'proxy-authorization',
};

final _sensitiveKey = RegExp(
  r'(password|passwd|token|secret|authorization|cookie|api[_-]?key)$',
  caseSensitive: false,
);

const _statusPhrases = <int, String>{
  200: 'OK',
  201: 'Created',
  204: 'No Content',
  301: 'Moved Permanently',
  302: 'Found',
  304: 'Not Modified',
  400: 'Bad Request',
  401: 'Unauthorized',
  403: 'Forbidden',
  404: 'Not Found',
  405: 'Method Not Allowed',
  408: 'Timeout',
  409: 'Conflict',
  429: 'Too Many Requests',
  500: 'Internal Server Error',
  502: 'Bad Gateway',
  503: 'Service Unavailable',
  504: 'Gateway Timeout',
};

enum HttpLogFilter { all, ok, client, server, error }

enum HttpBodyKind { empty, json, html, text }

class HttpRequestLog {
  HttpRequestLog({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.method,
    required this.url,
    required this.duration,
    this.status,
    this.error,
    this.requestHeaders = const {},
    this.requestBody,
    this.requestBodyBytes = 0,
    this.responseHeaders = const {},
    this.responseBody,
    this.responseBodyBytes = 0,
  });

  final String id;
  final DateTime startedAt;
  final DateTime endedAt;
  final String method;
  final String url;
  final Duration duration;
  final int? status;
  final String? error;
  final Map<String, String> requestHeaders;
  final String? requestBody;
  final int requestBodyBytes;
  final Map<String, String> responseHeaders;
  final String? responseBody;
  final int responseBodyBytes;

  DateTime get time => endedAt;

  bool get isTransportError => status == null;

  bool get is2xx => status != null && status! >= 200 && status! < 300;

  bool get is4xx => status != null && status! >= 400 && status! < 500;

  bool get is5xx => status != null && status! >= 500;

  String get path {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path.isEmpty) {
      return url;
    }
    return uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;
  }

  String get pathOnly {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.path.isEmpty) {
      return '/';
    }
    return uri.path;
  }

  String get host {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return '';
    }
    if (uri.hasPort && uri.port != 80 && uri.port != 443) {
      return '${uri.host}:${uri.port}';
    }
    return uri.host;
  }

  Map<String, String> get queryParameters => Uri.tryParse(url)?.queryParameters ?? const {};

  String get durationLabel {
    final ms = duration.inMilliseconds;
    if (ms < 1000) {
      return '$ms ms';
    }
    return '${(ms / 1000).toStringAsFixed(ms >= 10000 ? 1 : 2)} s';
  }

  String get startedClock => formatHttpClock(startedAt);

  String get endedClock => formatHttpClock(endedAt);

  String get statusLabel {
    if (status == null) {
      return '失败';
    }
    final phrase = _statusPhrases[status!] ?? '';
    return phrase.isEmpty ? '$status' : '$status $phrase';
  }

  String get requestSizeLabel => formatByteSize(requestBodyBytes);

  String get responseSizeLabel => formatByteSize(responseBodyBytes);

  String? get requestContentType => headerValue(requestHeaders, 'content-type');

  String? get responseContentType => headerValue(responseHeaders, 'content-type');

  bool matchesFilter(HttpLogFilter filter) {
    switch (filter) {
      case HttpLogFilter.all:
        return true;
      case HttpLogFilter.ok:
        return is2xx;
      case HttpLogFilter.client:
        return is4xx;
      case HttpLogFilter.server:
        return is5xx;
      case HttpLogFilter.error:
        return isTransportError;
    }
  }

  Map<String, String> displayRequestHeaders({required bool reveal}) =>
      reveal ? requestHeaders : redactHeaders(requestHeaders);

  Map<String, String> displayResponseHeaders({required bool reveal}) =>
      reveal ? responseHeaders : redactHeaders(responseHeaders);

  String? displayRequestBody({required bool reveal}) =>
      reveal ? requestBody : redactBodyString(requestBody);

  String? displayResponseBody({required bool reveal}) =>
      reveal ? responseBody : redactBodyString(responseBody);

  String toCurl({required bool reveal}) {
    final headers = displayRequestHeaders(reveal: reveal);
    final body = displayRequestBody(reveal: reveal);
    final buffer = StringBuffer('curl --request $method \\\n  --url ${_shQuote(url)}');
    final keys = headers.keys.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    for (final key in keys) {
      buffer.write(' \\\n  --header ${_shQuote('$key: ${headers[key]}')}');
    }
    if (body != null && body.trim().isNotEmpty) {
      buffer.write(' \\\n  --data ${_shQuote(body)}');
    }
    return buffer.toString();
  }

  String dump({required bool reveal}) {
    return [
      '$method $url',
      'status: $statusLabel',
      'duration: $durationLabel',
      'start: $startedClock',
      'end: $endedClock',
      if (error != null) 'error: $error',
      '',
      '--- request headers ---',
      formatHeaderBlock(displayRequestHeaders(reveal: reveal)),
      '',
      '--- request body ---',
      displayRequestBody(reveal: reveal) ?? '<empty>',
      '',
      '--- response headers ---',
      formatHeaderBlock(displayResponseHeaders(reveal: reveal)),
      '',
      '--- response body ---',
      displayResponseBody(reveal: reveal) ?? '<empty>',
    ].join('\n');
  }
}

class HttpRequestLogger extends ChangeNotifier {
  HttpRequestLogger._();

  static final HttpRequestLogger instance = HttpRequestLogger._();

  bool enabled = false;
  final List<HttpRequestLog> records = [];
  int _seq = 0;

  void setEnabled(bool value) {
    if (enabled == value) {
      return;
    }
    enabled = value;
    notifyListeners();
  }

  void clear() {
    if (records.isEmpty) {
      return;
    }
    records.clear();
    notifyListeners();
  }

  HttpRequestLog? byId(String id) {
    for (final record in records) {
      if (record.id == id) {
        return record;
      }
    }
    return null;
  }

  int count(HttpLogFilter filter, {String search = ''}) =>
      query(filter: filter, search: search).length;

  List<HttpRequestLog> query({HttpLogFilter filter = HttpLogFilter.all, String search = ''}) {
    final needle = search.trim().toLowerCase();
    return records.where((record) {
      if (!record.matchesFilter(filter)) {
        return false;
      }
      if (needle.isEmpty) {
        return true;
      }
      return record.url.toLowerCase().contains(needle) ||
          record.method.toLowerCase().contains(needle) ||
          '${record.status ?? ''}'.contains(needle);
    }).toList();
  }

  void capture({
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
    if (!enabled) {
      return;
    }
    final endedAt = DateTime.now();
    final safeDuration = duration.isNegative ? Duration.zero : duration;
    _seq += 1;
    records.insert(
      0,
      HttpRequestLog(
        id: '$_seq',
        startedAt: endedAt.subtract(safeDuration),
        endedAt: endedAt,
        method: method.toUpperCase(),
        url: url,
        duration: safeDuration,
        status: status,
        error: error == null || error.trim().isEmpty ? null : _truncate(error.trim()),
        requestHeaders: Map<String, String>.from(requestHeaders ?? const {}),
        requestBody: prettyBody(requestBody),
        requestBodyBytes: requestBody?.length ?? 0,
        responseHeaders: Map<String, String>.from(responseHeaders ?? const {}),
        responseBody: prettyBody(responseBody),
        responseBodyBytes: responseBody?.length ?? 0,
      ),
    );
    if (records.length > _maxRecords) {
      records.removeRange(_maxRecords, records.length);
    }
    notifyListeners();
  }
}

String formatHttpClock(DateTime time) {
  final local = time.toLocal();
  String pad(int value, [int width = 2]) => value.toString().padLeft(width, '0');
  return '${pad(local.hour)}:${pad(local.minute)}:${pad(local.second)}.${pad(local.millisecond, 3)}';
}

String formatByteSize(int bytes) {
  if (bytes <= 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String? headerValue(Map<String, String> headers, String name) {
  final target = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == target) {
      return entry.value;
    }
  }
  return null;
}

List<MapEntry<String, String>> sortedHeaders(Map<String, String> headers) {
  final entries = headers.entries.toList()
    ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
  return entries;
}

String formatHeaderBlock(Map<String, String> headers) {
  if (headers.isEmpty) {
    return '<none>';
  }
  return sortedHeaders(headers).map((entry) => '${entry.key}: ${entry.value}').join('\n');
}

HttpBodyKind bodyKind(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return HttpBodyKind.empty;
  }
  final trimmed = raw.trimLeft();
  if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
    return HttpBodyKind.json;
  }
  if (trimmed.startsWith('<')) {
    return HttpBodyKind.html;
  }
  return HttpBodyKind.text;
}

Map<String, String> redactHeaders(Map<String, String> headers) {
  final redacted = <String, String>{};
  headers.forEach((name, value) {
    redacted[name] = _sensitiveHeaderNames.contains(name.toLowerCase()) ? _mask(value) : value;
  });
  return redacted;
}

String? redactBodyString(String? raw) {
  if (raw == null) {
    return null;
  }
  final trimmed = raw.trim();
  if (trimmed.isEmpty) {
    return raw;
  }
  try {
    return _truncate(_pretty(_redactValue(jsonDecode(trimmed))));
  } catch (_) {
    return _truncate(raw);
  }
}

String? prettyBody(String? raw) {
  if (raw == null) {
    return null;
  }
  if (raw.trim().isEmpty) {
    return raw;
  }
  try {
    return _truncate(_pretty(jsonDecode(raw)));
  } catch (_) {
    return _truncate(raw);
  }
}

dynamic _redactValue(dynamic value) {
  if (value is Map) {
    return Map<String, dynamic>.fromEntries(
      value.entries.map((entry) {
        final key = entry.key.toString();
        if (_sensitiveKey.hasMatch(key) || _looksLikeSecretField(key, entry.value)) {
          return MapEntry(key, _mask(entry.value?.toString() ?? ''));
        }
        return MapEntry(key, _redactValue(entry.value));
      }),
    );
  }
  if (value is List) {
    return value.map(_redactValue).toList();
  }
  return value;
}

bool _looksLikeSecretField(String key, dynamic value) {
  if (key.toLowerCase() != 'key' || value is! String) {
    return false;
  }
  final text = value.trim();
  return text.startsWith('sk-') || text.length >= 24;
}

String _pretty(Object? value) {
  try {
    return const JsonEncoder.withIndent('  ').convert(value);
  } catch (_) {
    return value.toString();
  }
}

String _mask(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    return '••••••••';
  }
  if (text.toLowerCase().startsWith('bearer ') && text.length > 11) {
    return 'Bearer ${_mask(text.substring(7))}';
  }
  if (text.length <= 8) {
    return '••••••••';
  }
  return '${text.substring(0, 4)}••••••${text.substring(text.length - 4)}';
}

String _truncate(String value) {
  if (value.length <= _maxBodyChars) {
    return value;
  }
  return '${value.substring(0, _maxBodyChars)}\n…（已截断）';
}

String _shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";
