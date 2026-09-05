import 'dart:convert';
import 'dart:typed_data';

import 'package:vault/app/api/http.dart';
import 'package:vault/app/utils/format.dart';

const kModelProbePrompt = '只回复两个字：可用';
const kModelProbeImagePrompt = '红色圆，白底，简笔画';

class KeyTestPrep {
  const KeyTestPrep({
    required this.secret,
    required this.urls,
    required this.models,
    required this.baseUrl,
  });

  final String secret;
  final List<String> urls;
  final List<String> models;
  final String baseUrl;
}

enum ModelProbeKind { chat, claude, codex, embedding, image, audio, video, moderation }

enum ModelProbeStatus { pending, running, ok, fail, skipped }

class ModelProbeResult {
  const ModelProbeResult({
    required this.model,
    required this.kind,
    required this.status,
    required this.message,
    this.duration,
    this.prompt,
    this.reply,
    this.imageBytes,
  });

  final String model;
  final ModelProbeKind kind;
  final ModelProbeStatus status;
  final String message;
  final Duration? duration;
  final String? prompt;
  final String? reply;
  final Uint8List? imageBytes;

  bool get ok => status == ModelProbeStatus.ok;

  ModelProbeResult copyWith({
    ModelProbeStatus? status,
    String? message,
    Duration? duration,
    String? prompt,
    String? reply,
    Uint8List? imageBytes,
  }) {
    return ModelProbeResult(
      model: model,
      kind: kind,
      status: status ?? this.status,
      message: message ?? this.message,
      duration: duration ?? this.duration,
      prompt: prompt ?? this.prompt,
      reply: reply ?? this.reply,
      imageBytes: imageBytes ?? this.imageBytes,
    );
  }
}

class ProbeImageRef {
  const ProbeImageRef({this.bytes, this.url});

  final Uint8List? bytes;
  final String? url;
}

class _TextProbe {
  const _TextProbe({required this.kind, required this.payload});

  final ModelProbeKind kind;
  final Object payload;
}

String openAiPath(String baseUrl, String suffix) {
  final normalized = tryNormalizeBaseUrl(baseUrl) ?? baseUrl.trim();
  final trimmed = suffix.replaceFirst(RegExp(r'^/'), '');
  if (RegExp(r'/v1$', caseSensitive: false).hasMatch(normalized)) {
    return '/$trimmed';
  }
  return '/v1/$trimmed';
}

String modelsPathFor(String baseUrl) => openAiPath(baseUrl, 'models');

String modelProbeKindLabel(ModelProbeKind kind) {
  switch (kind) {
    case ModelProbeKind.chat:
      return '对话';
    case ModelProbeKind.claude:
      return 'Claude';
    case ModelProbeKind.codex:
      return 'Codex';
    case ModelProbeKind.embedding:
      return '向量';
    case ModelProbeKind.image:
      return '图像';
    case ModelProbeKind.audio:
      return '音频';
    case ModelProbeKind.video:
      return '视频';
    case ModelProbeKind.moderation:
      return '审核';
  }
}

bool isTextProbeKind(ModelProbeKind kind) {
  return kind == ModelProbeKind.chat ||
      kind == ModelProbeKind.claude ||
      kind == ModelProbeKind.codex;
}

ModelProbeKind classifyModelProbe(String model) {
  final name = model.trim().toLowerCase();
  if (RegExp(
    r'(moderation)',
  ).hasMatch(name)) {
    return ModelProbeKind.moderation;
  }
  if (RegExp(
    r'(text-embedding|embed|bge-|e5-|voyage|jina-clip|jina-embed)',
  ).hasMatch(name)) {
    return ModelProbeKind.embedding;
  }
  if (RegExp(
    r'(tts|whisper|speech-to|text-to-speech|fish-speech|suno|\basr\b)',
  ).hasMatch(name)) {
    return ModelProbeKind.audio;
  }
  if (RegExp(
    r'(sora|runway|kling|luma|veo\d|seedance|cogvideo|hailuo|minimax-video)',
  ).hasMatch(name)) {
    return ModelProbeKind.video;
  }
  if (RegExp(
    r'(dall-e|dalle|flux|stable-diffusion|\bsdxl\b|imagen|cogview|seedream|gpt-image|midjourney|ideogram)',
  ).hasMatch(name)) {
    return ModelProbeKind.image;
  }
  if (RegExp(
    r'(claude|anthropic|\bkiro\b)',
  ).hasMatch(name)) {
    return ModelProbeKind.claude;
  }
  if (RegExp(
    r'(codex)',
  ).hasMatch(name)) {
    return ModelProbeKind.codex;
  }
  return ModelProbeKind.chat;
}

List<String> modelIdsFromPayload(Object? payload) {
  final record = asRecord(payload);
  if (record['success'] == false) {
    throw ApiError(describeKeyProbeMessage(messageFromPayload(record, '读不了模型列表')));
  }
  final seen = <String>{};
  final ids = <String>[];
  void add(String raw) {
    final id = raw.trim();
    if (id.isEmpty || !seen.add(id)) {
      return;
    }
    ids.add(id);
  }

  for (final item in collectMaps(payload)) {
    add((item['id'] ?? item['model'] ?? item['name'] ?? '').toString());
  }
  final data = record['data'];
  if (data is List) {
    for (final item in data) {
      if (item is String) {
        add(item);
      }
    }
  }
  return ids;
}

void ensureOpenAiSuccess(Object? payload) {
  final record = asRecord(payload);
  if (record['success'] == false) {
    throw ApiError(messageFromPayload(record, '调用失败'));
  }
  final error = record['error'];
  if (error == null || error == '') {
    return;
  }
  if (error is Map) {
    throw ApiError((error['message'] ?? error['type'] ?? '调用失败').toString());
  }
  throw ApiError(error.toString());
}

String describeKeyProbeMessage(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return '无法调用';
  }
  final lower = text.toLowerCase();
  if (RegExp(r'invalid api key|incorrect api key|invalid[_ ]token|unauthorized|authentication').hasMatch(lower) ||
      text.contains('密钥无效') ||
      text.contains('令牌无效')) {
    return '密钥无效或已停用';
  }
  if (RegExp(r'quota|insufficient|no available channel|no available').hasMatch(lower) ||
      text.contains('额度不足') ||
      text.contains('余额不足') ||
      text.contains('配额')) {
    return '额度不足或没有可用渠道';
  }
  if (RegExp(r'allow.?ip|ip whitelist|ip 白名单|当前.?ip').hasMatch(lower) ||
      text.contains('IP 不在')) {
    return '当前 IP 不在这把密钥的允许范围内';
  }
  if (RegExp(r'too many requests|rate limit').hasMatch(lower)) {
    return '请求太频繁，请稍后再试';
  }
  if (RegExp(r'model.?not.?found|does not exist|unknown model').hasMatch(lower) ||
      text.contains('模型不存在')) {
    return '站点没有这个模型';
  }
  if (looksLikeResponsesOnly(text)) {
    return '这个模型不能走对话接口，需要用 Codex / Responses';
  }
  if (looksLikeClaudeOnly(text)) {
    return '这个模型不能走对话接口，需要用 Claude Messages';
  }
  return userFacingError(ApiError(text), '无法调用');
}

String describeKeyProbeError(Object error) {
  if (error is ApiError) {
    if (error.status == 401 || error.status == 403) {
      return describeKeyProbeMessage(error.message);
    }
    if (error.status == 404) {
      return '这个地址没有对应的调用接口';
    }
    if (error.status == 429) {
      return '请求太频繁，请稍后再试';
    }
    return describeKeyProbeMessage(error.message);
  }
  return userFacingError(error, '无法调用');
}

bool looksLikeMaxTokensError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('max_tokens') || lower.contains('max_completion_tokens');
}

bool looksLikeResponsesOnly(String message) {
  final lower = message.toLowerCase();
  return RegExp(
    r'responses api|/v1/responses|use the responses|only supported.{0,40}responses|please use.{0,40}responses',
  ).hasMatch(lower);
}

bool looksLikeClaudeOnly(String message) {
  final lower = message.toLowerCase();
  return RegExp(
    r'/v1/messages|messages api|anthropic|claude code|use the messages|x-api-key',
  ).hasMatch(lower);
}

bool looksLikeInputMustBeList(String message) {
  final lower = message.toLowerCase();
  return lower.contains('input must be a list') ||
      lower.contains('input should be a list') ||
      lower.contains('input: value is not valid');
}

bool looksLikeMissingEndpoint(Object error) {
  if (error is ApiError && (error.status == 404 || error.status == 405)) {
    return true;
  }
  final message = (error is ApiError ? error.message : error.toString()).toLowerCase();
  return RegExp(r'unknown path|no route|not found|not implemented|does not exist').hasMatch(message);
}

String? extractProbeReply(Object? payload) {
  final record = asRecord(payload);
  final choices = record['choices'];
  if (choices is List && choices.isNotEmpty) {
    final first = choices.first;
    if (first is Map) {
      final message = first['message'];
      final fromMessage = _textFromContent(message is Map ? message['content'] : null);
      if (fromMessage != null) {
        return fromMessage;
      }
      final text = first['text'];
      if (text is String && text.trim().isNotEmpty) {
        return text.trim();
      }
    }
  }
  final fromClaude = _textFromContent(record['content']);
  if (fromClaude != null) {
    return fromClaude;
  }
  final outputText = record['output_text'];
  if (outputText is String && outputText.trim().isNotEmpty) {
    return outputText.trim();
  }
  final output = record['output'];
  if (output is List) {
    final parts = <String>[];
    for (final item in output) {
      if (item is! Map) {
        continue;
      }
      final text = _textFromContent(item['content']) ??
          (item['text'] is String ? (item['text'] as String).trim() : null);
      if (text != null && text.isNotEmpty) {
        parts.add(text);
      }
    }
    if (parts.isNotEmpty) {
      return parts.join('\n');
    }
  }
  return null;
}

Uint8List? decodeProbeImageBytes(String raw) {
  var text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  if (text.startsWith('data:')) {
    final comma = text.indexOf(',');
    if (comma < 0) {
      return null;
    }
    text = text.substring(comma + 1);
  }
  text = text.replaceAll(RegExp(r'\s+'), '');
  try {
    final bytes = base64Decode(text);
    return bytes.isEmpty ? null : bytes;
  } catch (_) {
    return null;
  }
}

ProbeImageRef extractProbeImage(Object? payload) {
  ProbeImageRef? found;
  void take(ProbeImageRef item) {
    found ??= item;
  }

  void readValue(Object? value) {
    if (found != null || value == null) {
      return;
    }
    if (value is String) {
      final text = value.trim();
      if (text.isEmpty) {
        return;
      }
      if (text.startsWith('http://') ||
          text.startsWith('https://') ||
          text.startsWith('//') ||
          text.startsWith('data:image')) {
        if (text.startsWith('data:image')) {
          final bytes = decodeProbeImageBytes(text);
          if (bytes != null) {
            take(ProbeImageRef(bytes: bytes));
          }
          return;
        }
        take(ProbeImageRef(url: text.startsWith('//') ? 'https:$text' : text));
        return;
      }
      final bytes = decodeProbeImageBytes(text);
      if (bytes != null && looksLikeImageBytes(bytes)) {
        take(ProbeImageRef(bytes: bytes));
      }
      return;
    }
    if (value is Map) {
      final record = asRecord(value);
      readValue(record['b64_json'] ?? record['b64'] ?? record['image_base64']);
      readValue(record['url']);
      readValue(record['image_url']);
      readValue(record['image']);
    }
  }

  for (final item in collectMaps(payload)) {
    readValue(item);
    if (found != null) {
      return found!;
    }
  }
  final data = asRecord(payload)['data'];
  if (data is List) {
    for (final item in data) {
      readValue(item);
      if (found != null) {
        return found!;
      }
    }
  }
  return found ?? const ProbeImageRef();
}

bool looksLikeImageBytes(Uint8List bytes) {
  if (bytes.length < 8) {
    return false;
  }
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) {
    return true;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) {
    return true;
  }
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    return true;
  }
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    return true;
  }
  return bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46;
}

String? _textFromContent(Object? content) {
  if (content is String) {
    final text = content.trim();
    return text.isEmpty ? null : text;
  }
  if (content is List) {
    final parts = <String>[];
    for (final item in content) {
      if (item is String && item.trim().isNotEmpty) {
        parts.add(item.trim());
      } else if (item is Map) {
        final type = (item['type'] ?? '').toString().toLowerCase();
        if (type == 'thinking' || type == 'reasoning') {
          continue;
        }
        final text = item['text'] ?? item['output_text'] ?? item['input_text'];
        if (text is String && text.trim().isNotEmpty) {
          parts.add(text.trim());
        }
      }
    }
    return parts.isEmpty ? null : parts.join('');
  }
  return null;
}

String _okMessage(Duration duration) {
  return '可用 · ${duration.inMilliseconds}ms';
}

Future<List<String>> listApiKeyModels({
  required String baseUrl,
  required String apiKey,
}) async {
  final url = tryNormalizeBaseUrl(baseUrl) ?? baseUrl.trim();
  final payload = await requestJson<Object>(
    path: modelsPathFor(url),
    baseUrl: url,
    token: apiKey,
    timeout: const Duration(seconds: 20),
  );
  return modelIdsFromPayload(payload);
}

Future<ModelProbeResult> probeModel({
  required String baseUrl,
  required String apiKey,
  required String model,
  bool allowExpensive = false,
}) async {
  final kind = classifyModelProbe(model);
  if ((kind == ModelProbeKind.video || kind == ModelProbeKind.image) && !allowExpensive) {
    return ModelProbeResult(
      model: model,
      kind: kind,
      status: ModelProbeStatus.skipped,
      message: kind == ModelProbeKind.video
          ? '视频模型未自动出片，点这一行可单独测'
          : '图像模型未自动出图，点这一行可单独测',
    );
  }
  final url = tryNormalizeBaseUrl(baseUrl) ?? baseUrl.trim();
  final started = DateTime.now();
  try {
    switch (kind) {
      case ModelProbeKind.embedding:
        await _post(
          baseUrl: url,
          apiKey: apiKey,
          suffix: 'embeddings',
          data: {'model': model, 'input': 'ping'},
        );
        return _finished(model, kind, started);
      case ModelProbeKind.moderation:
        await _post(
          baseUrl: url,
          apiKey: apiKey,
          suffix: 'moderations',
          data: {'model': model, 'input': 'ping'},
        );
        return _finished(model, kind, started);
      case ModelProbeKind.image:
        final imageBytes = await _probeImage(
          baseUrl: url,
          apiKey: apiKey,
          model: model,
        );
        final duration = DateTime.now().difference(started);
        return ModelProbeResult(
          model: model,
          kind: kind,
          status: ModelProbeStatus.ok,
          message: _okMessage(duration),
          duration: duration,
          prompt: kModelProbeImagePrompt,
          imageBytes: imageBytes,
        );
      case ModelProbeKind.audio:
        await _post(
          baseUrl: url,
          apiKey: apiKey,
          suffix: 'audio/speech',
          data: {
            'model': model,
            'input': 'hi',
            'voice': 'alloy',
          },
          requireJson: false,
        );
        return _finished(model, kind, started);
      case ModelProbeKind.video:
        await _post(
          baseUrl: url,
          apiKey: apiKey,
          suffix: 'chat/completions',
          data: _chatBody(model, maxTokens: 1),
        );
        return _finished(model, kind, started);
      case ModelProbeKind.chat:
      case ModelProbeKind.claude:
      case ModelProbeKind.codex:
        final probed = await _probeTextModel(
          baseUrl: url,
          apiKey: apiKey,
          model: model,
          preferred: kind,
        );
        final reply = extractProbeReply(probed.payload);
        final duration = DateTime.now().difference(started);
        return ModelProbeResult(
          model: model,
          kind: probed.kind,
          status: ModelProbeStatus.ok,
          message: _okMessage(duration),
          duration: duration,
          prompt: kModelProbePrompt,
          reply: reply,
        );
    }
  } catch (error) {
    return ModelProbeResult(
      model: model,
      kind: kind,
      status: ModelProbeStatus.fail,
      message: describeKeyProbeError(error),
      duration: DateTime.now().difference(started),
      prompt: isTextProbeKind(kind)
          ? kModelProbePrompt
          : kind == ModelProbeKind.image
          ? kModelProbeImagePrompt
          : null,
    );
  }
}

ModelProbeResult _finished(String model, ModelProbeKind kind, DateTime started) {
  final duration = DateTime.now().difference(started);
  return ModelProbeResult(
    model: model,
    kind: kind,
    status: ModelProbeStatus.ok,
    message: _okMessage(duration),
    duration: duration,
  );
}

Future<Uint8List> _probeImage({
  required String baseUrl,
  required String apiKey,
  required String model,
}) async {
  Object? lastError;
  final seen = <String>{};
  for (final data in _imageBodies(model)) {
    final key = jsonEncode(data);
    if (!seen.add(key)) {
      continue;
    }
    try {
      final payload = await _post(
        baseUrl: baseUrl,
        apiKey: apiKey,
        suffix: 'images/generations',
        data: data,
        timeout: const Duration(seconds: 60),
      );
      return await _imageBytesFromPayload(payload, baseUrl: baseUrl, apiKey: apiKey);
    } catch (error) {
      lastError = error;
      if (_isFatalImageError(error)) {
        rethrow;
      }
    }
  }
  throw lastError ?? ApiError('没能生成图像');
}

Iterable<Map<String, Object?>> _imageBodies(String model) sync* {
  final name = model.toLowerCase();
  final sizes = name.contains('dall-e-3') ||
          name.contains('dalle-3') ||
          name.contains('gpt-image') ||
          name.contains('imagen')
      ? <String>['1024x1024']
      : <String>['256x256', '1024x1024'];
  final extras = <Map<String, Object?>>[
    if (name.contains('gpt-image')) {'quality': 'low'},
    <String, Object?>{},
  ];
  for (final extra in extras) {
    for (final size in sizes) {
      yield {
        'model': model,
        'prompt': kModelProbeImagePrompt,
        'n': 1,
        'size': size,
        'response_format': 'b64_json',
        ...extra,
      };
      yield {
        'model': model,
        'prompt': kModelProbeImagePrompt,
        'n': 1,
        'size': size,
        ...extra,
      };
    }
  }
}

Future<Uint8List> _imageBytesFromPayload(
  Object payload, {
  required String baseUrl,
  required String apiKey,
}) async {
  final extracted = extractProbeImage(payload);
  final embedded = extracted.bytes;
  if (embedded != null && looksLikeImageBytes(embedded)) {
    return embedded;
  }
  final rawUrl = extracted.url?.trim() ?? '';
  if (rawUrl.isEmpty) {
    throw ApiError('站点没有返回图像');
  }
  final url = rawUrl.startsWith('http') ? rawUrl : joinUrl(baseUrl, rawUrl);
  final bytes = await requestBytes(url: url, token: apiKey);
  if (!looksLikeImageBytes(bytes)) {
    throw ApiError('站点返回的不是图像');
  }
  return bytes;
}

bool _isFatalImageError(Object error) {
  if (error is ApiError &&
      (error.status == 401 || error.status == 403 || error.status == 429)) {
    return true;
  }
  final message = error is ApiError ? error.message : error.toString();
  final lower = message.toLowerCase();
  return lower.contains('invalid api key') ||
      lower.contains('密钥无效') ||
      lower.contains('额度不足') ||
      lower.contains('余额不足') ||
      lower.contains('insufficient') ||
      lower.contains('quota') ||
      ((lower.contains('model') || lower.contains('模型')) &&
          (lower.contains('not found') || lower.contains('does not exist') || lower.contains('不存在')));
}

Map<String, Object?> _chatBody(String model, {int? maxTokens, int? maxCompletionTokens}) {
  return {
    'model': model,
    'messages': [
      {'role': 'user', 'content': kModelProbePrompt},
    ],
    'stream': false,
    'max_tokens': ?maxTokens,
    'max_completion_tokens': ?maxCompletionTokens,
  };
}

Future<_TextProbe> _probeTextModel({
  required String baseUrl,
  required String apiKey,
  required String model,
  required ModelProbeKind preferred,
}) async {
  final tried = <ModelProbeKind>{};
  var next = preferred;
  Object? lastError;
  while (true) {
    tried.add(next);
    try {
      final payload = await _invokeTextProtocol(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        kind: next,
      );
      return _TextProbe(kind: next, payload: payload);
    } catch (error) {
      lastError = error;
      final fallback = _fallbackTextKind(error, tried);
      if (fallback == null) {
        throw lastError;
      }
      next = fallback;
    }
  }
}

ModelProbeKind? _fallbackTextKind(Object error, Set<ModelProbeKind> tried) {
  final message = error is ApiError ? error.message : error.toString();
  if (!tried.contains(ModelProbeKind.codex) && looksLikeResponsesOnly(message)) {
    return ModelProbeKind.codex;
  }
  if (!tried.contains(ModelProbeKind.claude) && looksLikeClaudeOnly(message)) {
    return ModelProbeKind.claude;
  }
  if ((tried.contains(ModelProbeKind.claude) || tried.contains(ModelProbeKind.codex)) &&
      !tried.contains(ModelProbeKind.chat) &&
      looksLikeMissingEndpoint(error)) {
    return ModelProbeKind.chat;
  }
  return null;
}

Future<Object> _invokeTextProtocol({
  required String baseUrl,
  required String apiKey,
  required String model,
  required ModelProbeKind kind,
}) {
  switch (kind) {
    case ModelProbeKind.claude:
      return _probeClaude(baseUrl: baseUrl, apiKey: apiKey, model: model);
    case ModelProbeKind.codex:
      return _probeCodex(baseUrl: baseUrl, apiKey: apiKey, model: model);
    default:
      return _probeChat(baseUrl: baseUrl, apiKey: apiKey, model: model);
  }
}

Future<Object> _probeChat({
  required String baseUrl,
  required String apiKey,
  required String model,
}) async {
  try {
    return await _post(
      baseUrl: baseUrl,
      apiKey: apiKey,
      suffix: 'chat/completions',
      data: _chatBody(model, maxTokens: 64),
    );
  } catch (error) {
    final message = error is ApiError ? error.message : error.toString();
    if (!looksLikeMaxTokensError(message)) {
      rethrow;
    }
    return _post(
      baseUrl: baseUrl,
      apiKey: apiKey,
      suffix: 'chat/completions',
      data: _chatBody(model, maxCompletionTokens: 64),
    );
  }
}

Future<Object> _probeClaude({
  required String baseUrl,
  required String apiKey,
  required String model,
}) {
  return _post(
    baseUrl: baseUrl,
    apiKey: apiKey,
    suffix: 'messages',
    data: {
      'model': model,
      'max_tokens': 64,
      'stream': false,
      'messages': [
        {'role': 'user', 'content': kModelProbePrompt},
      ],
    },
    headers: {
      'anthropic-version': '2023-06-01',
      'x-api-key': apiKey,
    },
    timeout: const Duration(seconds: 40),
  );
}

Future<Object> _probeCodex({
  required String baseUrl,
  required String apiKey,
  required String model,
}) async {
  try {
    return await _post(
      baseUrl: baseUrl,
      apiKey: apiKey,
      suffix: 'responses',
      data: {
        'model': model,
        'input': kModelProbePrompt,
        'max_output_tokens': 64,
        'stream': false,
      },
      timeout: const Duration(seconds: 45),
    );
  } catch (error) {
    final message = error is ApiError ? error.message : error.toString();
    if (!looksLikeInputMustBeList(message)) {
      rethrow;
    }
    return _post(
      baseUrl: baseUrl,
      apiKey: apiKey,
      suffix: 'responses',
      data: {
        'model': model,
        'input': [
          {
            'role': 'user',
            'content': [
              {'type': 'input_text', 'text': kModelProbePrompt},
            ],
          },
        ],
        'max_output_tokens': 64,
        'stream': false,
      },
      timeout: const Duration(seconds: 45),
    );
  }
}

Future<Object> _post({
  required String baseUrl,
  required String apiKey,
  required String suffix,
  required Object data,
  Duration timeout = const Duration(seconds: 25),
  bool requireJson = true,
  Map<String, String>? headers,
}) async {
  final payload = await requestJson<Object>(
    method: 'POST',
    path: openAiPath(baseUrl, suffix),
    baseUrl: baseUrl,
    token: apiKey,
    data: data,
    timeout: timeout,
    requireJson: requireJson,
    headers: headers,
  );
  ensureOpenAiSuccess(payload);
  return payload;
}
