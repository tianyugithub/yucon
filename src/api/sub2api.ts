import { ApiError, normalizeBaseUrl, requestJson, requestJsonDetailed } from '@/utils/http'
import type { TokenGroupOption } from '@/types/domain'

export interface Sub2Envelope<T = unknown> {
  code?: number
  message?: string
  reason?: string
  data?: T
}

export interface Sub2PublicSettings {
  turnstile_enabled?: boolean
  turnstile_site_key?: string
  tencent_captcha_enabled?: boolean
  aliyun_captcha_enabled?: boolean
  totp_enabled?: boolean
  site_name?: string
  site_logo?: string
  site_subtitle?: string
  version?: string
}

export interface Sub2User {
  id: number
  username?: string
  email?: string
  role?: string
  balance?: number
  status?: 'active' | 'disabled' | string
}

export interface Sub2AuthResponse {
  access_token: string
  refresh_token?: string
  expires_in?: number
  token_type?: string
  user: Sub2User
}

export interface Sub2TotpChallenge {
  requires_2fa: true
  temp_token?: string
  user_email_masked?: string
}

export interface Sub2Key {
  id: number
  name?: string
  key?: string
  status?: 'active' | 'inactive' | 'quota_exhausted' | 'expired' | string
  group_id?: number | null
  group?: { id?: number; name?: string; rate_multiplier?: number; description?: string | null }
  quota?: number
  quota_used?: number
  expires_at?: string | null
  created_at?: string
  last_used_at?: string | null
  ip_whitelist?: string[]
}

export interface Sub2UsageLog {
  id?: number
  api_key_id?: number
  model?: string
  input_tokens?: number
  output_tokens?: number
  actual_cost?: number
  total_cost?: number
  created_at?: string
  api_key?: { name?: string }
}

export interface Sub2DashboardStats {
  total_api_keys?: number
  active_api_keys?: number
  total_requests?: number
  total_actual_cost?: number
  today_requests?: number
  today_actual_cost?: number
}

export interface Sub2Group {
  id: number
  name: string
  description?: string | null
  rate_multiplier?: number
  status?: string
}

export interface Sub2ConnectInput {
  baseUrl: string
  email?: string
  password?: string
  turnstileToken?: string
  accessToken?: string
  refreshToken?: string
}

export interface Sub2ConnectResult {
  baseUrl: string
  accessToken: string
  refreshToken: string
  user: Sub2User
  settings: Sub2PublicSettings
}

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' ? (value as Record<string, unknown>) : {}

const readNumber = (value: unknown, fallback = 0): number => {
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue : fallback
}

const collectItems = <T>(data: unknown): T[] => {
  if (Array.isArray(data)) {
    return data as T[]
  }
  const record = asRecord(data)
  if (Array.isArray(record.items)) {
    return record.items as T[]
  }
  if (Array.isArray(record.data)) {
    return record.data as T[]
  }
  return []
}

const friendlySub2Message = (message: string, reason = ''): string => {
  const text = `${reason} ${message}`.toLowerCase()
  if (text.includes('turnstile') || reason === 'TURNSTILE_VERIFICATION_FAILED') {
    return '需要完成 Cloudflare 人机验证。请在页面上完成验证后重试。'
  }
  if (text.includes('invalid') && (text.includes('credential') || text.includes('password') || text.includes('email'))) {
    return '邮箱或密码不正确'
  }
  return message || '请求失败'
}

const unwrap = <T>(payload: Sub2Envelope<T>, fallbackMessage: string): T => {
  const code = payload?.code
  if (typeof code === 'number' && code !== 0) {
    throw new ApiError(friendlySub2Message(payload.message || fallbackMessage, payload.reason), code)
  }
  if (payload?.data === undefined || payload.data === null) {
    throw new ApiError(friendlySub2Message(payload?.message || fallbackMessage, payload?.reason))
  }
  return payload.data
}

const requestSub2 = async <T>(options: {
  baseUrl: string
  path: string
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  token?: string
  data?: unknown
}): Promise<T> => {
  try {
    const payload = await requestJson<Sub2Envelope<T>>({
      baseUrl: options.baseUrl,
      path: options.path,
      method: options.method,
      token: options.token,
      data: options.data
    })
    return unwrap(payload, '请求失败')
  } catch (error) {
    if (error instanceof ApiError) {
      const raw = error.message || ''
      throw new ApiError(friendlySub2Message(raw), error.status)
    }
    throw error
  }
}

export const isSub2TotpChallenge = (value: unknown): value is Sub2TotpChallenge =>
  Boolean(value && typeof value === 'object' && (value as Sub2TotpChallenge).requires_2fa === true)

export const fetchPublicSettings = async (baseUrl: string): Promise<Sub2PublicSettings> => {
  const payload = await requestJson<Sub2Envelope<Sub2PublicSettings>>({
    baseUrl,
    path: '/api/v1/settings/public'
  })
  if (payload && typeof payload === 'object' && 'turnstile_enabled' in payload) {
    return payload as unknown as Sub2PublicSettings
  }
  if (typeof payload?.code === 'number' && payload.code !== 0) {
    throw new ApiError(friendlySub2Message(payload.message || '读取站点设置失败', payload.reason))
  }
  return (payload?.data ?? {}) as Sub2PublicSettings
}

export const loginSub2Account = async (
  baseUrl: string,
  email: string,
  password: string,
  turnstileToken?: string
): Promise<Sub2AuthResponse | Sub2TotpChallenge> => {
  try {
    const result = await requestJsonDetailed<Sub2Envelope<Sub2AuthResponse | Sub2TotpChallenge>>({
      baseUrl,
      path: '/api/v1/auth/login',
      method: 'POST',
      data: {
        email: email.trim(),
        password,
        ...(turnstileToken ? { turnstile_token: turnstileToken } : {})
      }
    })
    const payload = result.data
    if (typeof payload?.code === 'number' && payload.code !== 0) {
      throw new ApiError(friendlySub2Message(payload.message || '登录失败', payload.reason), result.status)
    }
    const data = payload?.data
    if (!data) {
      throw new ApiError(friendlySub2Message(payload?.message || '登录失败', payload?.reason), result.status)
    }
    return data
  } catch (error) {
    if (error instanceof ApiError) {
      throw new ApiError(friendlySub2Message(error.message), error.status)
    }
    throw error
  }
}

export const fetchCurrentSub2User = async (baseUrl: string, accessToken: string): Promise<Sub2User> =>
  requestSub2<Sub2User>({
    baseUrl,
    path: '/api/v1/auth/me',
    token: accessToken
  })

export const refreshSub2Token = async (
  baseUrl: string,
  refreshToken: string
): Promise<Pick<Sub2AuthResponse, 'access_token' | 'refresh_token' | 'expires_in'>> =>
  requestSub2({
    baseUrl,
    path: '/api/v1/auth/refresh',
    method: 'POST',
    data: { refresh_token: refreshToken }
  })

export const fetchSub2Keys = async (baseUrl: string, accessToken: string): Promise<Sub2Key[]> => {
  const data = await requestSub2<unknown>({
    baseUrl,
    path: '/api/v1/keys?page=1&page_size=100',
    token: accessToken
  })
  return collectItems<Sub2Key>(data)
}

export const fetchSub2KeyById = async (
  baseUrl: string,
  accessToken: string,
  remoteId: number
): Promise<Sub2Key> =>
  requestSub2<Sub2Key>({
    baseUrl,
    path: `/api/v1/keys/${remoteId}`,
    token: accessToken
  })

export const createSub2Key = async (
  baseUrl: string,
  accessToken: string,
  body: Record<string, unknown>
): Promise<Sub2Key> =>
  requestSub2<Sub2Key>({
    baseUrl,
    path: '/api/v1/keys',
    method: 'POST',
    token: accessToken,
    data: body
  })

export const updateSub2Key = async (
  baseUrl: string,
  accessToken: string,
  remoteId: number,
  body: Record<string, unknown>
): Promise<Sub2Key> =>
  requestSub2<Sub2Key>({
    baseUrl,
    path: `/api/v1/keys/${remoteId}`,
    method: 'PUT',
    token: accessToken,
    data: body
  })

export const deleteSub2Key = async (baseUrl: string, accessToken: string, remoteId: number): Promise<void> => {
  await requestSub2<unknown>({
    baseUrl,
    path: `/api/v1/keys/${remoteId}`,
    method: 'DELETE',
    token: accessToken
  })
}

export const fetchSub2UsageLogs = async (baseUrl: string, accessToken: string): Promise<Sub2UsageLog[]> => {
  const data = await requestSub2<unknown>({
    baseUrl,
    path: '/api/v1/usage?page=1&page_size=50',
    token: accessToken
  })
  return collectItems<Sub2UsageLog>(data)
}

export const fetchSub2DashboardStats = async (
  baseUrl: string,
  accessToken: string
): Promise<Sub2DashboardStats | null> => {
  try {
    return await requestSub2<Sub2DashboardStats>({
      baseUrl,
      path: '/api/v1/usage/dashboard/stats',
      token: accessToken
    })
  } catch {
    return null
  }
}

export const fetchSub2Groups = async (baseUrl: string, accessToken: string): Promise<TokenGroupOption[]> => {
  try {
    const groups = await requestSub2<Sub2Group[] | { items?: Sub2Group[] }>({
      baseUrl,
      path: '/api/v1/groups/available',
      token: accessToken
    })
    const list = Array.isArray(groups) ? groups : collectItems<Sub2Group>(groups)
    return list
      .filter((group) => group && group.id && group.status !== 'inactive')
      .map((group) => ({
        name: group.name,
        desc: group.description && group.description !== group.name ? group.description : group.name,
        ratio: readNumber(group.rate_multiplier, 1),
        ratioLabel: `×${readNumber(group.rate_multiplier, 1)}`,
        remoteId: group.id
      }))
      .sort((left, right) => left.name.localeCompare(right.name))
  } catch {
    return []
  }
}

export const connectSub2Account = async (input: Sub2ConnectInput): Promise<Sub2ConnectResult> => {
  const baseUrl = normalizeBaseUrl(input.baseUrl)
  const existingToken = input.accessToken?.trim() || ''
  if (existingToken) {
    const settings = await fetchPublicSettings(baseUrl)
    const user = await fetchCurrentSub2User(baseUrl, existingToken)
    return {
      baseUrl,
      accessToken: existingToken,
      refreshToken: input.refreshToken?.trim() || '',
      user,
      settings
    }
  }
  const email = input.email?.trim() || ''
  const password = input.password || ''
  if (!email || !password) {
    throw new ApiError('请填写邮箱和密码')
  }
  const settings = await fetchPublicSettings(baseUrl)
  if (settings.turnstile_enabled && !input.turnstileToken?.trim()) {
    throw new ApiError('该站点开启了 Cloudflare 人机验证，请先完成验证')
  }
  const login = await loginSub2Account(baseUrl, email, password, input.turnstileToken)
  if (isSub2TotpChallenge(login)) {
    throw new ApiError('该账号启用了两步验证，钥仓暂不支持，请先在站点关闭后重试')
  }
  const user = login.user?.id ? login.user : await fetchCurrentSub2User(baseUrl, login.access_token)
  return {
    baseUrl,
    accessToken: login.access_token,
    refreshToken: login.refresh_token || '',
    user,
    settings
  }
}

export { normalizeBaseUrl }
