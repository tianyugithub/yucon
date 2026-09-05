import 'package:vault/app/api/http.dart';
import 'package:vault/app/models/domain.dart';

String formatCompactCount(num count) {
  final value = count.floor().clamp(0, 1 << 30);
  return value > 99 ? '99+' : '$value';
}

String formatCurrency(num value) =>
    '\$${value.toStringAsFixed(2).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';

String formatLogMoney(num value) {
  final negative = value < 0;
  final abs = value.abs();
  String raw;
  if (abs == 0) {
    raw = '0.00';
  } else if (abs < 0.01) {
    raw = abs.toStringAsFixed(6).replaceFirst(RegExp(r'0+$'), '');
    if (!raw.contains('.')) {
      raw = '$raw.00';
    } else {
      final decimals = raw.split('.')[1];
      if (decimals.length < 2) {
        raw = abs.toStringAsFixed(2);
      }
    }
  } else {
    raw = abs.toStringAsFixed(2);
  }
  final parts = raw.split('.');
  final whole = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
  final rendered = parts.length == 1 ? whole : '$whole.${parts[1]}';
  return '${negative ? '-' : ''}\$$rendered';
}

String formatDateTime(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '—';
  }
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) {
    return '时间未知';
  }
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${pad(date.month)}/${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}';
}

String formatDateTimeFull(String? iso) {
  if (iso == null || iso.isEmpty) {
    return '—';
  }
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) {
    return '时间未知';
  }
  String pad(int value) => value.toString().padLeft(2, '0');
  return '${date.year}-${pad(date.month)}-${pad(date.day)} ${pad(date.hour)}:${pad(date.minute)}:${pad(date.second)}';
}

String formatGroupedInt(num value) {
  return value.round().toString().replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (match) => ',',
  );
}

String formatUseTime(num? value) {
  if (value == null || value <= 0) {
    return '';
  }
  final seconds = value > 10000 ? value / 1000 : value.toDouble();
  if (seconds < 1) {
    return '${(seconds * 1000).round()}ms';
  }
  if (seconds < 10) {
    final text = seconds.toStringAsFixed(1);
    return text.endsWith('.0') ? '${seconds.round()}s' : '${text}s';
  }
  return '${seconds.round()}s';
}

String usageLogTypeLabel(int type) {
  switch (type) {
    case 1:
      return '充值';
    case 2:
      return '消费';
    case 3:
      return '管理';
    case 4:
      return '系统';
    case 5:
      return '错误';
    case 6:
      return '退款';
    case 7:
      return '登录';
    default:
      return '调用';
  }
}

String formatUsageQuota(double amount, int type) {
  final text = formatLogMoney(amount);
  if (type == 1 || type == 6) {
    return '+$text';
  }
  if (amount == 0) {
    return text;
  }
  return '-$text';
}

String formatShortDate(String iso) {
  final date = DateTime.tryParse(iso)?.toLocal();
  if (date == null) {
    return '未知日期';
  }
  return '${date.month}月${date.day}日';
}

String maskSecret(String? value) {
  if (value == null || value.isEmpty) {
    return '尚未保存';
  }
  if (value.length <= 8) {
    return '••••••••';
  }
  return '${value.substring(0, 4)}••••••${value.substring(value.length - 4)}';
}

String displayDomain(String value) =>
    value.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');

String? tryNormalizeBaseUrl(String value) {
  try {
    return normalizeBaseUrl(value);
  } catch (_) {
    return null;
  }
}

List<String> parseExtraApiUrls(String text, {required String baseUrl}) {
  final base = tryNormalizeBaseUrl(baseUrl)?.toLowerCase();
  final seen = <String>{?base};
  final urls = <String>[];
  for (final part in text.split(RegExp(r'[\n,，]+'))) {
    final normalized = tryNormalizeBaseUrl(part);
    if (normalized == null || normalized.isEmpty) {
      continue;
    }
    if (!seen.add(normalized.toLowerCase())) {
      continue;
    }
    urls.add(normalized);
  }
  return urls;
}

List<String> apiCopyUrlsFor(Account account) {
  final urls = <String>[];
  final seen = <String>{};
  void add(String raw) {
    final normalized = tryNormalizeBaseUrl(raw);
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    if (!seen.add(normalized.toLowerCase())) {
      return;
    }
    urls.add(normalized);
  }

  add(account.baseUrl);
  for (final url in account.apiUrls) {
    add(url);
  }
  return urls;
}

String hostnameOf(String baseUrl) {
  try {
    return Uri.parse(normalizeBaseUrl(baseUrl)).host;
  } catch (_) {
    final cleaned = baseUrl.replaceFirst(RegExp(r'^https?://'), '').replaceFirst(RegExp(r'/$'), '');
    return cleaned.isEmpty ? '未命名站点' : cleaned;
  }
}
