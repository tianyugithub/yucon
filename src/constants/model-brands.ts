export type ModelVendorKey =
  | 'openai'
  | 'claude'
  | 'gemini'
  | 'google'
  | 'deepseek'
  | 'qwen'
  | 'zhipu'
  | 'grok'
  | 'meta'
  | 'mistral'
  | 'kimi'
  | 'doubao'
  | 'minimax'
  | 'cohere'
  | 'perplexity'
  | 'hunyuan'
  | 'baidu'
  | 'yi'
  | 'nvidia'
  | 'unknown'

export interface ModelBrand {
  key: ModelVendorKey
  label: string
}

const RULES: Array<{ key: Exclude<ModelVendorKey, 'unknown'>; label: string; test: RegExp }> = [
  { key: 'claude', label: 'Claude', test: /(claude|anthropic)/i },
  { key: 'deepseek', label: 'DeepSeek', test: /deepseek/i },
  { key: 'zhipu', label: '智谱', test: /(glm|chatglm|zhipu|cogview|cogvideo)/i },
  { key: 'qwen', label: '通义千问', test: /(qwen|qwq|qvq|dashscope)/i },
  { key: 'gemini', label: 'Gemini', test: /(gemini|gemma|imagen|lyria)/i },
  { key: 'google', label: 'Google', test: /google/i },
  { key: 'grok', label: 'Grok', test: /(grok|\bxai\b)/i },
  { key: 'kimi', label: 'Kimi', test: /(moonshot|kimi|^k2-|\bk2\b)/i },
  { key: 'doubao', label: '豆包', test: /(doubao|seedream|seedance|^seed-)/i },
  { key: 'mistral', label: 'Mistral', test: /(mistral|mixtral|pixtral|codestral)/i },
  { key: 'meta', label: 'Meta', test: /(llama|meta-llama)/i },
  { key: 'minimax', label: 'MiniMax', test: /(minimax|abab|hailuo)/i },
  { key: 'cohere', label: 'Cohere', test: /(command-r|cohere)/i },
  { key: 'perplexity', label: 'Perplexity', test: /(perplexity|sonar)/i },
  { key: 'hunyuan', label: '混元', test: /hunyuan/i },
  { key: 'baidu', label: '文心', test: /(ernie|wenxin|baidu)/i },
  { key: 'yi', label: '零一万物', test: /(^yi-|\byi-large|01-ai)/i },
  { key: 'nvidia', label: 'NVIDIA', test: /(nvidia|nemotron)/i },
  {
    key: 'openai',
    label: 'OpenAI',
    test: /(^gpt-|\/gpt-|openai|chatgpt|^o[1-9]\b|dall-e|dalle|^sora|gpt-oss|codex|whisper|tts-1|text-embedding)/i
  }
]

const FALLBACK: ModelBrand = { key: 'unknown', label: '其他' }

export const brandFromKey = (key: ModelVendorKey): ModelBrand => {
  const rule = RULES.find((item) => item.key === key)
  return rule ? { key: rule.key, label: rule.label } : FALLBACK
}

export const detectModelBrand = (model: string): ModelBrand => {
  const name = model.trim()
  if (!name) {
    return FALLBACK
  }
  const matched = RULES.find((rule) => rule.test.test(name))
  return matched ? { key: matched.key, label: matched.label } : FALLBACK
}

export const modelBrandIconSrc = (key: ModelVendorKey): string => {
  if (key === 'unknown') {
    return ''
  }
  return `/static/model-brands/${key}.png`
}
