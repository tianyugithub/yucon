import 'dart:convert';

import 'package:vault/app/utils/format.dart';
import 'package:vault/app/utils/quota.dart';

class UsageLogContentInfo {
  const UsageLogContentInfo({
    required this.preview,
    this.message,
    this.statusCode,
    this.type,
    this.traceId,
    this.fields = const [],
  });

  final String preview;
  final String? message;
  final int? statusCode;
  final String? type;
  final String? traceId;
  final List<UsageLogField> fields;
}

class UsageLogField {
  const UsageLogField(this.label, this.value);

  final String label;
  final String value;
}

const _otherLabels = <String, String>{
  'cache_tokens': '缓存读取',
  'cache_read_tokens': '缓存读取',
  'cached_tokens': '缓存读取',
  'cache_creation_tokens': '缓存写入',
  'cache_write_tokens': '缓存写入',
  'cache_creation_tokens_5m': '缓存写入（5 分钟）',
  'cache_creation_tokens_1h': '缓存写入（1 小时）',
  'cache_ratio': '缓存倍率',
  'cache_creation_ratio': '缓存写入倍率',
  'cache_creation_ratio_5m': '缓存写入倍率（5 分钟）',
  'cache_creation_ratio_1h': '缓存写入倍率（1 小时）',
  'frt': '首字耗时',
  'model_ratio': '模型倍率',
  'completion_ratio': '补全倍率',
  'model_price': '模型价格',
  'group_ratio': '分组倍率',
  'user_group_ratio': '用户分组倍率',
  'audio_ratio': '音频输入倍率',
  'audio_completion_ratio': '音频输出倍率',
  'image_ratio': '图片倍率',
  'upstream_model_name': '上游模型',
  'is_model_mapped': '模型已映射',
  'reasoning_effort': '推理力度',
  'billing_mode': '计费方式',
  'billing_source': '计费来源',
  'matched_tier': '命中档位',
  'image': '图片',
  'image_output': '图片 tokens',
  'audio': '音频',
  'audio_input': '音频输入',
  'audio_output': '音频输出',
  'audio_input_price': '音频输入价格',
  'text_input': '文本输入',
  'text_output': '文本输出',
  'web_search': '联网搜索',
  'web_search_call_count': '联网搜索次数',
  'web_search_price': '联网搜索价格',
  'file_search': '文件搜索',
  'file_search_call_count': '文件搜索次数',
  'file_search_price': '文件搜索价格',
  'image_generation_call': '图片生成',
  'image_generation_call_price': '图片生成价格',
  'claude': 'Claude 协议',
  'ws': 'WebSocket',
  'request_conversion': '请求转换',
  'is_system_prompt_overwritten': '系统提示已覆盖',
  'request_path': '请求路径',
  'login_method': '登录方式',
  'user_agent': 'User-Agent',
  'use_channel': '实际渠道',
  'channel_id': '渠道 ID',
  'local_count_tokens': '本地计费',
  'admin_info': '管理信息',
};

const _hiddenOtherKeys = {
  'cache_tokens',
  'cache_read_tokens',
  'cached_tokens',
  'cache_creation_tokens',
  'cache_write_tokens',
  'cache_creation_tokens_5m',
  'cache_creation_tokens_1h',
  'expr_b64',
  'audit_info',
};

UsageLogContentInfo parseUsageLogContent(String content) {
  final text = content.trim();
  if (text.isEmpty) {
    return const UsageLogContentInfo(preview: '');
  }

  int? statusCode;
  String? traceId;
  Map<String, dynamic>? payload;

  final statusMatch = RegExp(r'status_code\s*=\s*(\d+)').firstMatch(text);
  if (statusMatch != null) {
    statusCode = int.tryParse(statusMatch.group(1)!);
  }

  final traceMatch = RegExp(
    r'\(\s*traceid:\s*([^)]+?)\s*\)',
    caseSensitive: false,
  ).firstMatch(text);
  if (traceMatch != null) {
    traceId = traceMatch.group(1)?.trim();
    if (traceId != null && traceId.isEmpty) {
      traceId = null;
    }
  }

  final jsonStart = text.indexOf('{');
  final jsonEnd = text.lastIndexOf('}');
  if (jsonStart >= 0 && jsonEnd > jsonStart) {
    try {
      final decoded = jsonDecode(text.substring(jsonStart, jsonEnd + 1));
      if (decoded is Map) {
        payload = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }

  String? message;
  String? type;
  if (payload != null) {
    final error = payload['error'];
    if (error is Map) {
      final record = Map<String, dynamic>.from(error);
      final extracted = record['message']?.toString().trim();
      if (extracted != null && extracted.isNotEmpty) {
        message = extracted;
      }
      final extractedType = record['type']?.toString().trim();
      if (extractedType != null && extractedType.isNotEmpty) {
        type = extractedType;
      }
    } else {
      final extracted = payload['message']?.toString().trim();
      if (extracted != null && extracted.isNotEmpty) {
        message = extracted;
      }
    }
  }

  final preview = (message != null && message.isNotEmpty) ? message : text;
  final fields = <UsageLogField>[
    if (statusCode != null) UsageLogField('状态码', '$statusCode'),
    if (type != null && type.isNotEmpty) UsageLogField('错误类型', type),
    if (preview.isNotEmpty) UsageLogField('说明', preview),
    if (traceId != null) UsageLogField('Trace ID', traceId),
  ];

  return UsageLogContentInfo(
    preview: preview,
    message: message,
    statusCode: statusCode,
    type: type,
    traceId: traceId,
    fields: fields,
  );
}

List<UsageLogField> usageLogOtherFields(Map<String, dynamic> other) {
  final fields = <UsageLogField>[];
  _collectOtherFields(other, fields, '');
  return fields;
}

void _collectOtherFields(
  Map<String, dynamic> source,
  List<UsageLogField> fields,
  String prefix,
) {
  source.forEach((rawKey, value) {
    final key = rawKey.toString();
    if (_hiddenOtherKeys.contains(key) && prefix.isEmpty) {
      return;
    }
    if (value is Map) {
      _collectOtherFields(Map<String, dynamic>.from(value), fields, key);
      return;
    }
    if (_isEmptyOtherValue(value)) {
      return;
    }
    final label = _otherLabel(key, prefix);
    fields.add(UsageLogField(label, _formatOtherValue(key, value)));
  });
}

bool _isEmptyOtherValue(Object? value) {
  if (value == null) {
    return true;
  }
  if (value is bool) {
    return !value;
  }
  if (value is num) {
    return value == 0 || value == -1;
  }
  if (value is String) {
    return value.trim().isEmpty;
  }
  if (value is List) {
    return value.isEmpty;
  }
  if (value is Map) {
    return value.isEmpty;
  }
  return false;
}

String _otherLabel(String key, String prefix) {
  final own = _otherLabels[key];
  if (own != null) {
    return own;
  }
  if (prefix.isNotEmpty) {
    final parent = _otherLabels[prefix];
    if (parent != null) {
      return '$parent · $key';
    }
  }
  return key;
}

String _formatOtherValue(String key, Object? value) {
  if (value is bool) {
    return value ? '是' : '否';
  }
  if (value is List) {
    return value.map((item) => item.toString()).where((item) => item.isNotEmpty).join('、');
  }
  if (value is num) {
    if (key == 'frt') {
      return value >= 1000 ? formatUseTime(value) : '${value.round()}ms';
    }
    if (key.contains('ratio') || key.contains('price')) {
      return _formatDecimal(value);
    }
    if (value == value.roundToDouble()) {
      return formatGroupedInt(value);
    }
    return _formatDecimal(value);
  }
  return value.toString();
}

String _formatDecimal(num value) {
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  var text = value.toStringAsFixed(4);
  text = text.replaceFirst(RegExp(r'0+$'), '');
  return text.endsWith('.') ? '${text}0' : text;
}

String formatUsageLogOtherDump(Map<String, dynamic> other) {
  final fields = usageLogOtherFields(other);
  if (fields.isEmpty) {
    return prettyJsonMap(other);
  }
  return fields.map((field) => '${field.label}：${field.value}').join('\n');
}
