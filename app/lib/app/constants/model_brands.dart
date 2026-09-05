class ModelBrand {
  const ModelBrand({required this.key, required this.label});

  final String key;
  final String label;
}

class _BrandRule {
  const _BrandRule(this.key, this.label, this.pattern);

  final String key;
  final String label;
  final String pattern;
}

const _fallback = ModelBrand(key: 'unknown', label: '其他');

const _rules = [
  _BrandRule('claude', 'Claude', r'(claude|anthropic|\bkiro\b)'),
  _BrandRule('deepseek', 'DeepSeek', r'deepseek'),
  _BrandRule('zhipu', '智谱', r'(glm|chatglm|zhipu|cogview|cogvideo)'),
  _BrandRule('qwen', '通义千问', r'(qwen|qwq|qvq|dashscope)'),
  _BrandRule('gemini', 'Gemini', r'(gemini|gemma|imagen|lyria)'),
  _BrandRule('google', 'Google', r'google'),
  _BrandRule('grok', 'Grok', r'(grok|\bxai\b)'),
  _BrandRule('kimi', 'Kimi', r'(moonshot|kimi|^k2-|\bk2\b)'),
  _BrandRule('doubao', '豆包', r'(doubao|seedream|seedance|^seed-)'),
  _BrandRule('mistral', 'Mistral', r'(mistral|mixtral|pixtral|codestral)'),
  _BrandRule('meta', 'Meta', r'(llama|meta-llama)'),
  _BrandRule('minimax', 'MiniMax', r'(minimax|abab|hailuo)'),
  _BrandRule('cohere', 'Cohere', r'(command-r|cohere)'),
  _BrandRule('perplexity', 'Perplexity', r'(perplexity|sonar)'),
  _BrandRule('hunyuan', '混元', r'hunyuan'),
  _BrandRule('baidu', '文心', r'(ernie|wenxin|baidu)'),
  _BrandRule('yi', '零一万物', r'(^yi-|\byi-large|01-ai)'),
  _BrandRule('nvidia', 'NVIDIA', r'(nvidia|nemotron)'),
  _BrandRule(
    'openai',
    'OpenAI',
    r'(^gpt-|/gpt-|openai|chatgpt|^o[1-9]\b|dall-e|dalle|^sora|gpt-oss|codex|whisper|tts-1|text-embedding)',
  ),
];

ModelBrand brandFromKey(String key) {
  for (final rule in _rules) {
    if (rule.key == key) {
      return ModelBrand(key: rule.key, label: rule.label);
    }
  }
  return _fallback;
}

ModelBrand detectModelBrand(String model) {
  final name = model.trim();
  if (name.isEmpty) {
    return _fallback;
  }
  for (final rule in _rules) {
    if (RegExp(rule.pattern, caseSensitive: false).hasMatch(name)) {
      return ModelBrand(key: rule.key, label: rule.label);
    }
  }
  return _fallback;
}

String? modelBrandAsset(String key) {
  if (key == 'unknown' || key.isEmpty) {
    return null;
  }
  return 'assets/model-brands/$key.png';
}
