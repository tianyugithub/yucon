import 'dart:convert';

import 'package:vault/app/models/domain.dart';

const defaultQuotaPerUnit = 500000.0;

double roundMoney(num value) => (value * 100).round() / 100;

double quotaToMoney(num quota, [num quotaPerUnit = defaultQuotaPerUnit]) {
  final unit = quotaPerUnit > 0 ? quotaPerUnit : defaultQuotaPerUnit;
  return roundMoney(quota / unit);
}

double? parseTopupAmountFromContent(String content) {
  final text = content.trim();
  if (text.isEmpty) {
    return null;
  }
  final patterns = [
    RegExp(r'(?:充值金额|充值额度)[^0-9]{0,12}([0-9]+(?:\.[0-9]+)?)'),
    RegExp(r'\$\s*([0-9]+(?:\.[0-9]+)?)\s*额度'),
  ];
  for (final pattern in patterns) {
    final match = pattern.firstMatch(text);
    if (match == null) {
      continue;
    }
    final value = double.tryParse(match.group(1) ?? '');
    if (value != null && value > 0) {
      return roundMoney(value);
    }
  }
  return null;
}

double resolveUsageQuotaCost({
  required int type,
  required num quota,
  required String content,
  num quotaPerUnit = defaultQuotaPerUnit,
}) {
  final fromQuota = quotaToMoney(quota, quotaPerUnit);
  if (type != 1 && type != 6) {
    return fromQuota;
  }
  if (fromQuota.abs() >= 0.01) {
    return fromQuota;
  }
  final parsed = parseTopupAmountFromContent(content);
  if (parsed != null) {
    return parsed;
  }
  if (quota.abs() >= 0.01 && quota.abs() < 100000) {
    return roundMoney(quota);
  }
  return 0;
}

int moneyToQuota(num money, [num quotaPerUnit = defaultQuotaPerUnit]) {
  final unit = quotaPerUnit > 0 ? quotaPerUnit : defaultQuotaPerUnit;
  return (money * unit).round();
}

String? unixToIso(num? value) {
  if (value == null || value <= 0) {
    return null;
  }
  final millis = value > 1000000000000 ? value.toDouble() : value * 1000;
  final date = DateTime.fromMillisecondsSinceEpoch(millis.round(), isUtc: true);
  return date.toIso8601String();
}

String? createdAtToIso(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return unixToIso(value);
  }
  final text = value.toString().trim();
  if (text.isEmpty || text == 'null') {
    return null;
  }
  if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(text)) {
    return unixToIso(num.tryParse(text));
  }
  return DateTime.tryParse(text)?.toUtc().toIso8601String();
}

String formatLocalYmd(DateTime date) {
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)}';
}

DateWindow dateWindowFor(UsageTimeRange range, [DateTime? now]) {
  final local = now ?? DateTime.now();
  if (range == UsageTimeRange.all) {
    return const DateWindow();
  }
  final today = DateTime(local.year, local.month, local.day);
  final end = DateTime(local.year, local.month, local.day, 23, 59, 59);
  final start = switch (range) {
    UsageTimeRange.today => today,
    UsageTimeRange.days7 => today.subtract(const Duration(days: 6)),
    UsageTimeRange.days30 => today.subtract(const Duration(days: 29)),
    UsageTimeRange.all => today,
  };
  return DateWindow(
    startUnix: start.millisecondsSinceEpoch ~/ 1000,
    endUnix: end.millisecondsSinceEpoch ~/ 1000,
    startDate: formatLocalYmd(start),
    endDate: formatLocalYmd(end),
  );
}

int isoToUnix(String? value) {
  if (value == null || value.isEmpty) {
    return -1;
  }
  final date = DateTime.tryParse(value);
  if (date == null) {
    return -1;
  }
  return date.millisecondsSinceEpoch ~/ 1000;
}

int dateInputToUnix(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return -1;
  }
  if (trimmed.contains('T') || trimmed.contains(' ')) {
    return isoToUnix(trimmed.replaceFirst(' ', 'T'));
  }
  final date = DateTime.tryParse('${trimmed}T23:59:59');
  if (date == null) {
    return -1;
  }
  return date.millisecondsSinceEpoch ~/ 1000;
}

String formatGroupRatio(Object? value) {
  if (value == '自动' || value == 'auto') {
    return '自动';
  }
  final ratio = num.tryParse(value.toString());
  if (ratio == null) {
    return '—';
  }
  final text = ratio % 1 == 0 ? ratio.toInt().toString() : ratio.toString();
  return '×$text';
}

String weekdayLabel(String iso) {
  const labels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六'];
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) {
    return '今天';
  }
  return labels[date.weekday % 7];
}

String isoNow() => DateTime.now().toUtc().toIso8601String();

String localDateKey(String iso) {
  final date = DateTime.tryParse(iso)?.toLocal() ?? DateTime.now();
  return '${date.year}-${date.month}-${date.day}';
}

List<String> splitList(String value) => value
    .split(RegExp(r'[\n,，]'))
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

String? describeQuotaAlert({
  required bool enabled,
  required double threshold,
  required List<String> lowAccountNames,
}) {
  if (!enabled || lowAccountNames.isEmpty) {
    return null;
  }
  final amount = threshold.toStringAsFixed(2);
  if (lowAccountNames.length == 1) {
    return '${lowAccountNames.first} 额度低于 \$$amount';
  }
  return '${lowAccountNames.length} 个账号额度低于 \$$amount';
}

bool isMaskedKey(String? value) =>
    value == null ||
    value.isEmpty ||
    value.contains('*') ||
    value.contains('•') ||
    value.contains('·');

Map<String, dynamic> parseUsageLogOther(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty || text == '{}' || text == 'null') {
      return {};
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  return {};
}

int usageLogOtherInt(Map<String, dynamic> other, List<String> keys) {
  for (final key in keys) {
    final value = other[key];
    if (value is num) {
      return value.toInt();
    }
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed != null) {
      return parsed.toInt();
    }
  }
  return 0;
}

int usageLogCacheReadTokens(Map<String, dynamic> other) => usageLogOtherInt(
  other,
  const ['cache_tokens', 'cache_read_tokens', 'cached_tokens'],
);

int usageLogCacheWriteTokens(Map<String, dynamic> other) {
  final split =
      usageLogOtherInt(other, const ['cache_creation_tokens_5m']) +
      usageLogOtherInt(other, const ['cache_creation_tokens_1h']);
  if (split > 0) {
    return split;
  }
  return usageLogOtherInt(other, const [
    'cache_creation_tokens',
    'cache_write_tokens',
  ]);
}

String prettyJsonMap(Map<String, dynamic> value) {
  if (value.isEmpty) {
    return '';
  }
  return const JsonEncoder.withIndent('  ').convert(value);
}

extension UsageLogTokens on UsageLog {
  int get cacheReadTokens => usageLogCacheReadTokens(other);
  int get cacheWriteTokens => usageLogCacheWriteTokens(other);
  int get totalTokens => promptTokens + completionTokens;
}
