import 'package:flutter_test/flutter_test.dart';
import 'package:vault/app/api/http.dart';
import 'package:vault/app/api/key_probe.dart';

void main() {
  test('builds OpenAI paths for site and /v1 bases', () {
    expect(modelsPathFor('https://api.example.com'), '/v1/models');
    expect(openAiPath('https://api.example.com/v1', 'chat/completions'), '/chat/completions');
    expect(openAiPath('https://api.example.com', 'embeddings'), '/v1/embeddings');
  });

  test('classifies models by usage kind', () {
    expect(classifyModelProbe('gpt-4o-mini'), ModelProbeKind.chat);
    expect(classifyModelProbe('gpt-4o-audio-preview'), ModelProbeKind.chat);
    expect(classifyModelProbe('text-embedding-3-small'), ModelProbeKind.embedding);
    expect(classifyModelProbe('dall-e-3'), ModelProbeKind.image);
    expect(classifyModelProbe('flux-schnell'), ModelProbeKind.image);
    expect(classifyModelProbe('sora-2'), ModelProbeKind.video);
    expect(classifyModelProbe('tts-1'), ModelProbeKind.audio);
    expect(classifyModelProbe('omni-moderation-latest'), ModelProbeKind.moderation);
    expect(classifyModelProbe('claude-sonnet-4-5'), ModelProbeKind.claude);
    expect(classifyModelProbe('anthropic/claude-opus-4'), ModelProbeKind.claude);
    expect(classifyModelProbe('gpt-5-codex'), ModelProbeKind.codex);
    expect(classifyModelProbe('codex-mini-latest'), ModelProbeKind.codex);
  });

  test('reads model ids from OpenAI and NewAPI payloads', () {
    expect(
      modelIdsFromPayload({
        'object': 'list',
        'data': [
          {'id': 'gpt-4o'},
          {'id': 'gpt-4o-mini'},
        ],
      }),
      ['gpt-4o', 'gpt-4o-mini'],
    );
    expect(
      modelIdsFromPayload({
        'success': true,
        'data': ['gpt-4o', 'gpt-4o'],
      }),
      ['gpt-4o'],
    );
  });

  test('treats success false as unreadable model list', () {
    expect(
      () => modelIdsFromPayload({'success': false, 'message': '无效的令牌'}),
      throwsA(isA<ApiError>()),
    );
  });

  test('skips image and video until explicitly allowed', () async {
    final image = await probeModel(
      baseUrl: 'https://api.example.com',
      apiKey: 'sk-test',
      model: 'dall-e-3',
    );
    expect(image.status, ModelProbeStatus.skipped);
    final video = await probeModel(
      baseUrl: 'https://api.example.com',
      apiKey: 'sk-test',
      model: 'sora-2',
    );
    expect(video.status, ModelProbeStatus.skipped);
  });

  test('maps max_tokens errors for chat retry', () {
    expect(looksLikeMaxTokensError('Unsupported parameter: max_tokens'), isTrue);
    expect(looksLikeMaxTokensError('invalid api key'), isFalse);
  });

  test('reads OpenAI error objects', () {
    expect(
      () => ensureOpenAiSuccess({
        'error': {'message': 'model does not exist'},
      }),
      throwsA(isA<ApiError>()),
    );
    ensureOpenAiSuccess({'id': 'chatcmpl-1'});
  });

  test('extracts replies from chat, Claude and Codex payloads', () {
    expect(
      extractProbeReply({
        'choices': [
          {
            'message': {'role': 'assistant', 'content': '可用'},
          },
        ],
      }),
      '可用',
    );
    expect(
      extractProbeReply({
        'type': 'message',
        'content': [
          {'type': 'thinking', 'thinking': 'hmm'},
          {'type': 'text', 'text': '可用'},
        ],
      }),
      '可用',
    );
    expect(
      extractProbeReply({
        'output_text': '可用',
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': '可用'},
            ],
          },
        ],
      }),
      '可用',
    );
  });

  test('detects protocol-only models', () {
    expect(
      looksLikeResponsesOnly('This model is only supported in the Responses API'),
      isTrue,
    );
    expect(looksLikeClaudeOnly('please use /v1/messages'), isTrue);
    expect(looksLikeInputMustBeList('Input must be a list'), isTrue);
  });

  test('extracts image bytes and urls from generation payloads', () {
    const png =
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
    final fromB64 = extractProbeImage({
      'data': [
        {'b64_json': png},
      ],
    });
    expect(fromB64.bytes, isNotNull);
    expect(looksLikeImageBytes(fromB64.bytes!), isTrue);

    final fromUrl = extractProbeImage({
      'data': [
        {'url': 'https://cdn.example.com/out.png'},
      ],
    });
    expect(fromUrl.url, 'https://cdn.example.com/out.png');

    final fromDataUri = extractProbeImage({
      'data': [
        {'url': 'data:image/png;base64,$png'},
      ],
    });
    expect(fromDataUri.bytes, isNotNull);
    expect(looksLikeImageBytes(fromDataUri.bytes!), isTrue);
  });
}
