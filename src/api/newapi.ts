import { ApiError, asCookieAuth, mergeCookies, NATIVE_COOKIE_AUTH, normalizeBaseUrl, requestJson, requestJsonDetailed } from '@/utils/http'
import { DEFAULT_QUOTA_PER_UNIT, formatGroupRatio } from '@/utils/quota'
import type { TokenGroupOption } from '@/types/domain'

export interface NewApiEnvelope<T = unknown> {
  success?: boolean
  message?: string
  data?: T
}

export interface NewApiUser {
  id: number
  username?: string
  display_name?: string
  email?: string
  group?: string
  quota?: number
  used_quota?: number
  request_count?: number
  status?: number
}

export interface NewApiToken {
  id: number
  name?: string
  key?: string
  status?: number
  remain_quota?: number
  used_quota?: number
  unlimited_quota?: boolean
  expired_time?: number
  created_time?: number
  accessed_time?: number
  group?: string
  model_limits?: string
  model_limits_enabled?: boolean
  allow_ips?: string | null
  cross_group_retry?: boolean
}

export interface NewApiUsageLog {
  id?: number
  type?: number
  token_name?: string
  model_name?: string
  quota?: number
  prompt_tokens?: number
  completion_tokens?: number
  created_at?: number
  content?: string
}

export interface NewApiCheckinStats {
  enabled?: boolean
  checked_in_today?: boolean
  records?: Array<{ checkin_date: string; quota_awarded: number }>
  stats?: {
    checked_in_today?: boolean
    records?: Array<{ checkin_date: string; quota_awarded: number }>
  }
}

export interface ConnectInput {
  baseUrl: string
  username?: string
  password?: string
  accessToken?: string
  userId?: string
}

export interface ConnectResult {
  baseUrl: string
  accessToken: string
  user: NewApiUser
  quotaPerUnit: number
  checkinEnabled: boolean
}

const unwrap = <T>(payload: NewApiEnvelope<T>, fallbackMessage: string): T => {
  if (payload && payload.success === false) {
    throw new ApiError(friendlyAuthMessage(payload.message || fallbackMessage))
  }
  if (payload?.data === undefined || payload.data === null) {
    throw new ApiError(friendlyAuthMessage(payload?.message || fallbackMessage))
  }
  return payload.data
}

const friendlyAuthMessage = (message: string): string => {
  if (message.includes('New-Api-User')) {
    return '该站点需要数字用户 ID。请打开站点「个人设置」查看用户 ID，并与系统访问令牌一起填写。'
  }
  if (message.includes('access token 无效')) {
    return '系统访问令牌无效。请重新生成，不要使用 sk- 开头的模型调用 Key。'
  }
  return message
}

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' ? (value as Record<string, unknown>) : {}

const readNumber = (value: unknown, fallback = 0): number => {
  const numberValue = Number(value)
  return Number.isFinite(numberValue) ? numberValue : fallback
}

export const fetchSiteStatus = async (
  baseUrl: string
): Promise<{ quotaPerUnit: number; checkinEnabled: boolean; systemName: string }> => {
  try {
    const payload = await requestJson<NewApiEnvelope<Record<string, unknown>>>({
      baseUrl,
      path: '/api/status'
    })
    const data = asRecord(payload.data)
    return {
      quotaPerUnit: readNumber(data.quota_per_unit, DEFAULT_QUOTA_PER_UNIT) || DEFAULT_QUOTA_PER_UNIT,
      checkinEnabled: Boolean(data.checkin_enabled),
      systemName: String(data.system_name || '')
    }
  } catch {
    return {
      quotaPerUnit: DEFAULT_QUOTA_PER_UNIT,
      checkinEnabled: false,
      systemName: ''
    }
  }
}

const pickToken = (...values: unknown[]): string => {
  for (const value of values) {
    if (typeof value === 'string' && value.trim() && value !== 'null' && value !== 'undefined') {
      return value.trim()
    }
  }
  return ''
}

const asUser = (value: unknown): NewApiUser | null => {
  if (!value || typeof value !== 'object') {
    return null
  }
  const record = value as Record<string, unknown>
  const id = readNumber(record.id)
  if (!id) {
    return null
  }
  return {
    id,
    username: record.username ? String(record.username) : undefined,
    display_name: record.display_name ? String(record.display_name) : undefined,
    email: record.email ? String(record.email) : undefined,
    group: record.group ? String(record.group) : undefined,
    quota: readNumber(record.quota),
    used_quota: readNumber(record.used_quota),
    request_count: readNumber(record.request_count),
    status: readNumber(record.status, 1)
  }
}

const extractIssuedToken = (payload: NewApiEnvelope<unknown>): string => {
  const data = payload.data
  if (typeof data === 'string') {
    return pickToken(data)
  }
  const record = asRecord(data)
  return pickToken(record.access_token, record.token, record.key)
}

const fetchUserWithAuth = async (
  baseUrl: string,
  token: string,
  userId?: string,
  cookie?: string
): Promise<NewApiUser> => {
  const payload = await requestJson<NewApiEnvelope<NewApiUser>>({
    baseUrl,
    path: '/api/user/self',
    token,
    userId,
    cookie
  })
  return unwrap(payload, '读取用户资料失败')
}

const issueAccessToken = async (
  baseUrl: string,
  cookie: string,
  userId: string
): Promise<string> => {
  for (const method of ['GET', 'POST'] as const) {
    try {
      const payload = await requestJson<NewApiEnvelope<unknown>>({
        baseUrl,
        path: '/api/user/token',
        method,
        cookie,
        userId
      })
      if (payload.success === false) {
        continue
      }
      const token = extractIssuedToken(payload)
      if (token) {
        return token
      }
    } catch {
      // Some sites only support one of GET / POST.
    }
  }
  return ''
}

export const connectAccount = async (input: ConnectInput): Promise<ConnectResult> => {
  const baseUrl = normalizeBaseUrl(input.baseUrl)
  const status = await fetchSiteStatus(baseUrl)
  let accessToken = input.accessToken?.trim() || ''
  const providedUserId = input.userId?.trim() || ''

  if (!accessToken) {
    const username = input.username?.trim() || ''
    const password = input.password || ''
    if (!username || !password) {
      throw new ApiError('请填写用户名和密码，或改用系统访问令牌')
    }
    const login = await requestJsonDetailed<NewApiEnvelope<Record<string, unknown> | string>>({
      baseUrl,
      path: '/api/user/login',
      method: 'POST',
      data: { username, password }
    })
    const raw = unwrap(login.data, '登录失败')
    const data = asRecord(raw)
    if (data.require_2fa) {
      throw new ApiError('该账号启用了两步验证，请改用系统访问令牌连接')
    }
    const nestedUser = asUser(data.user) || asUser(data)
    const userId = String(nestedUser?.id || data.id || providedUserId || '')
    const nested = asRecord(data.user)
    accessToken = pickToken(
      data.access_token,
      data.token,
      nested.access_token,
      nested.token,
      typeof data.session === 'string' ? data.session : undefined
    )
    const sessionCookie = mergeCookies(login.cookies)

    if (accessToken) {
      const user = nestedUser || (await fetchUserWithAuth(baseUrl, accessToken, userId))
      return {
        baseUrl,
        accessToken,
        user,
        quotaPerUnit: status.quotaPerUnit,
        checkinEnabled: status.checkinEnabled
      }
    }

    if (sessionCookie) {
      try {
        const self = await requestJsonDetailed<NewApiEnvelope<NewApiUser>>({
          baseUrl,
          path: '/api/user/self',
          cookie: sessionCookie,
          userId
        })
        const user = unwrap(self.data, '读取用户资料失败')
        return {
          baseUrl,
          accessToken: asCookieAuth(mergeCookies(sessionCookie, self.cookies)),
          user,
          quotaPerUnit: status.quotaPerUnit,
          checkinEnabled: status.checkinEnabled
        }
      } catch {
        const issued = await issueAccessToken(baseUrl, sessionCookie, userId)
        if (issued) {
          const user = await fetchUserWithAuth(baseUrl, issued, userId)
          return {
            baseUrl,
            accessToken: issued,
            user,
            quotaPerUnit: status.quotaPerUnit,
            checkinEnabled: status.checkinEnabled
          }
        }
      }
    }

    if (userId) {
      try {
        const user = await fetchUserWithAuth(baseUrl, NATIVE_COOKIE_AUTH, userId)
        return {
          baseUrl,
          accessToken: NATIVE_COOKIE_AUTH,
          user,
          quotaPerUnit: status.quotaPerUnit,
          checkinEnabled: status.checkinEnabled
        }
      } catch {
        // H5 has no native cookie jar for the upstream site.
      }
    }

    throw new ApiError(
      '登录成功，但站点没有返回可保存的会话。请改用「访问令牌」，在站点个人设置中创建系统访问令牌。'
    )
  }

  if (!providedUserId) {
    throw new ApiError('请填写数字用户 ID。该站点的系统访问令牌需要与 New-Api-User 一起使用。')
  }

  const user = await fetchCurrentUser(baseUrl, accessToken, providedUserId)
  return {
    baseUrl,
    accessToken,
    user,
    quotaPerUnit: status.quotaPerUnit,
    checkinEnabled: status.checkinEnabled
  }
}

export const fetchCurrentUser = async (
  baseUrl: string,
  accessToken: string,
  userId?: string
): Promise<NewApiUser> => {
  const payload = await requestJson<NewApiEnvelope<NewApiUser>>({
    baseUrl,
    path: '/api/user/self',
    token: accessToken,
    userId
  })
  return unwrap(payload, '读取用户资料失败')
}

const collectTokens = (data: unknown): NewApiToken[] => {
  if (Array.isArray(data)) {
    return data as NewApiToken[]
  }
  const record = asRecord(data)
  if (Array.isArray(record.items)) {
    return record.items as NewApiToken[]
  }
  if (Array.isArray(record.data)) {
    return record.data as NewApiToken[]
  }
  return []
}

export const fetchTokens = async (
  baseUrl: string,
  accessToken: string,
  userId: string
): Promise<NewApiToken[]> => {
  const tokens: NewApiToken[] = []
  for (const page of [1, 0]) {
    const payload = await requestJson<NewApiEnvelope<unknown>>({
      baseUrl,
      path: `/api/token/?p=${page}&size=100`,
      token: accessToken,
      userId
    })
    const pageTokens = collectTokens(payload.success === false ? [] : payload.data)
    if (pageTokens.length) {
      tokens.push(...pageTokens)
      break
    }
    if (payload.success === false && page === 1) {
      continue
    }
    if (page === 1 && pageTokens.length === 0) {
      continue
    }
    break
  }
  return tokens
}

export const fetchUsageLogs = async (
  baseUrl: string,
  accessToken: string,
  userId: string
): Promise<NewApiUsageLog[]> => {
  const payload = await requestJson<NewApiEnvelope<unknown>>({
    baseUrl,
    path: '/api/log/self?p=1&page_size=50&type=2',
    token: accessToken,
    userId
  })
  if (payload.success === false) {
    return []
  }
  return collectTokens(payload.data) as unknown as NewApiUsageLog[]
}

export const fetchCheckinStatus = async (
  baseUrl: string,
  accessToken: string,
  userId: string
): Promise<NewApiCheckinStats | null> => {
  try {
    const month = new Date().toISOString().slice(0, 7)
    const payload = await requestJson<NewApiEnvelope<NewApiCheckinStats>>({
      baseUrl,
      path: `/api/user/checkin?month=${month}`,
      token: accessToken,
      userId
    })
    if (payload.success === false) {
      return { enabled: false }
    }
    return payload.data ?? { enabled: true }
  } catch {
    return null
  }
}

export const doCheckin = async (
  baseUrl: string,
  accessToken: string,
  userId: string
): Promise<{ quotaAwarded: number; message: string }> => {
  const payload = await requestJson<NewApiEnvelope<{ quota_awarded?: number; checkin_date?: string }>>(
    {
      baseUrl,
      path: '/api/user/checkin',
      method: 'POST',
      token: accessToken,
      userId,
      data: {}
    }
  )
  if (payload.success === false) {
    throw new ApiError(payload.message || '签到失败')
  }
  return {
    quotaAwarded: readNumber(payload.data?.quota_awarded),
    message: payload.message || '签到成功'
  }
}

export const createToken = async (
  baseUrl: string,
  accessToken: string,
  userId: string,
  body: Record<string, unknown>
): Promise<void> => {
  const payload = await requestJson<NewApiEnvelope<unknown>>({
    baseUrl,
    path: '/api/token/',
    method: 'POST',
    token: accessToken,
    userId,
    data: body
  })
  if (payload.success === false) {
    throw new ApiError(payload.message || '创建 API Key 失败')
  }
}

export const updateToken = async (
  baseUrl: string,
  accessToken: string,
  userId: string,
  body: Record<string, unknown>,
  statusOnly = false
): Promise<void> => {
  const path = statusOnly ? '/api/token/?status_only=true' : '/api/token/'
  const payload = await requestJson<NewApiEnvelope<unknown>>({
    baseUrl,
    path,
    method: 'PUT',
    token: accessToken,
    userId,
    data: body
  })
  if (payload.success === false) {
    throw new ApiError(payload.message || '更新 API Key 失败')
  }
}

export const deleteToken = async (
  baseUrl: string,
  accessToken: string,
  userId: string,
  remoteId: number
): Promise<void> => {
  const payload = await requestJson<NewApiEnvelope<unknown>>({
    baseUrl,
    path: `/api/token/${remoteId}`,
    method: 'DELETE',
    token: accessToken,
    userId
  })
  if (payload.success === false) {
    throw new ApiError(payload.message || '删除 API Key 失败')
  }
}

export const revealTokenKey = async (
  baseUrl: string,
  accessToken: string,
  userId: string,
  remoteId: number
): Promise<string> => {
  const payload = await requestJson<NewApiEnvelope<{ key?: string }>>({
    baseUrl,
    path: `/api/token/${remoteId}/key`,
    method: 'POST',
    token: accessToken,
    userId,
    data: {}
  })
  const key = unwrap(payload, '读取完整 Key 失败').key
  if (!key) {
    throw new ApiError('站点未返回完整 Key')
  }
  return key
}

const collectStrings = (data: unknown): string[] => {
  if (Array.isArray(data)) {
    return data.map((item) => String(item)).filter(Boolean)
  }
  const record = asRecord(data)
  if (Array.isArray(record.items)) {
    return record.items.map((item) => String(item)).filter(Boolean)
  }
  if (Array.isArray(record.models)) {
    return record.models.map((item) => String(item)).filter(Boolean)
  }
  return []
}

const toGroupOption = (name: string, desc: string, ratio: unknown): TokenGroupOption => ({
  name,
  desc: desc && desc !== name ? desc : name === 'auto' ? '按系统自动分组规则路由' : desc || name,
  ratio: typeof ratio === 'number' && Number.isFinite(ratio) ? ratio : Number.isFinite(Number(ratio)) ? Number(ratio) : null,
  ratioLabel: formatGroupRatio(name === 'auto' ? '自动' : ratio)
})

const parseUserGroups = (data: unknown): TokenGroupOption[] => {
  const record = asRecord(data)
  const groups: TokenGroupOption[] = []
  for (const [name, value] of Object.entries(record)) {
    if (!name.trim()) {
      continue
    }
    if (typeof value === 'string' || typeof value === 'number') {
      const text = String(value)
      const ratioMatch = text.match(/倍率[:：]?\s*([0-9.]+|自动)/)
      const desc = text.replace(/[，,]\s*倍率[:：]?.*/, '')
      groups.push(
        toGroupOption(name, desc, name === 'auto' ? '自动' : ratioMatch?.[1] ?? (typeof value === 'number' ? value : 1))
      )
      continue
    }
    const item = asRecord(value)
    groups.push(toGroupOption(name, String(item.desc || item.name || name), item.ratio ?? (name === 'auto' ? '自动' : 1)))
  }
  return groups.sort((left, right) => {
    if (left.name === 'auto') {
      return -1
    }
    if (right.name === 'auto') {
      return 1
    }
    if (left.name === 'default') {
      return -1
    }
    if (right.name === 'default') {
      return 1
    }
    return left.name.localeCompare(right.name)
  })
}

export const fetchUserGroups = async (
  baseUrl: string,
  accessToken: string,
  userId: string
): Promise<TokenGroupOption[]> => {
  const tryPaths = ['/api/user/self/groups', '/api/user/groups']
  for (const path of tryPaths) {
    try {
      const payload = await requestJson<NewApiEnvelope<unknown>>({
        baseUrl,
        path,
        token: accessToken,
        userId
      })
      if (payload.success === false) {
        continue
      }
      const groups = parseUserGroups(payload.data)
      if (groups.length) {
        return groups
      }
    } catch {
      // try the next known endpoint
    }
  }

  try {
    const payload = await requestJson<NewApiEnvelope<unknown> & {
      usable_group?: Record<string, string>
      group_ratio?: Record<string, number>
    }>({
      baseUrl,
      path: '/api/pricing',
      token: accessToken,
      userId
    })
    const usable = payload.usable_group || asRecord(asRecord(payload.data).usable_group)
    const ratios = payload.group_ratio || asRecord(asRecord(payload.data).group_ratio)
    const groups = Object.keys(usable)
      .filter(Boolean)
      .map((name) => toGroupOption(name, String(usable[name] || name), name === 'auto' ? '自动' : ratios[name] ?? 1))
    if (groups.length) {
      return groups.sort((left, right) => left.name.localeCompare(right.name))
    }
  } catch {
    // fall through to empty
  }
  return []
}

export const fetchGroupModels = async (
  baseUrl: string,
  accessToken: string,
  userId: string,
  group: string
): Promise<string[]> => {
  const suffix = group ? `?group=${encodeURIComponent(group)}` : ''
  const tryPaths = [`/api/user/models${suffix}`, `/api/user/available_models${suffix}`, '/api/user/available_models']
  for (const path of tryPaths) {
    try {
      const payload = await requestJson<NewApiEnvelope<unknown>>({
        baseUrl,
        path,
        token: accessToken,
        userId
      })
      if (payload.success === false) {
        continue
      }
      const models = collectStrings(payload.data)
      if (models.length) {
        return [...new Set(models)]
      }
    } catch {
      // try the next known endpoint
    }
  }

  try {
    const payload = await requestJson<NewApiEnvelope<Array<{ model_name?: string; enable_groups?: string[] }>>>({
      baseUrl,
      path: '/api/pricing',
      token: accessToken,
      userId
    })
    const rows = Array.isArray(payload.data) ? payload.data : []
    return [...new Set(
      rows
        .filter((row) => !group || group === 'auto' || (row.enable_groups || []).includes(group))
        .map((row) => String(row.model_name || ''))
        .filter(Boolean)
    )]
  } catch {
    return []
  }
}

export { normalizeBaseUrl }
