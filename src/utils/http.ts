export class ApiError extends Error {
  status?: number

  constructor(message: string, status?: number) {
    super(message)
    this.name = 'ApiError'
    this.status = status
  }
}

export const isAuthExpiredError = (error: unknown): boolean => {
  if (!(error instanceof ApiError)) {
    return false
  }
  if (error.status === 401 || error.status === 403) {
    return true
  }
  const text = `${error.message} ${error.status ?? ''}`.toLowerCase()
  return /unauthor|unauthenticated|token.*(expir|invalid)|jwt.*(expir|invalid)|登录过期|未登录|凭证无效/.test(
    text
  )
}

export interface RequestOptions {
  method?: 'GET' | 'POST' | 'PUT' | 'DELETE'
  path: string
  baseUrl: string
  token?: string
  userId?: string
  cookie?: string
  data?: unknown
  timeout?: number
}

export interface RequestResult<T> {
  data: T
  cookies: string
  status: number
}

const PROXY_PREFIX = '/__yucon'
const YUCON_COOKIES_FIELD = '__yucon_cookies'
export const COOKIE_AUTH_PREFIX = 'cookie:'
export const NATIVE_COOKIE_AUTH = 'cookie:native'

const normalizeBaseUrl = (value: string): string => {
  const trimmed = value.trim().replace(/\/+$/, '')
  if (!trimmed) {
    throw new ApiError('请填写站点地址')
  }
  if (/^https?:\/\//i.test(trimmed)) {
    return trimmed
  }
  return `https://${trimmed}`
}

const joinUrl = (baseUrl: string, path: string): string => {
  const normalizedPath = path.startsWith('/') ? path : `/${path}`
  return `${normalizeBaseUrl(baseUrl)}${normalizedPath}`
}

const shouldUseDevProxy = (): boolean => {
  // #ifdef H5
  return Boolean(import.meta.env.DEV)
  // #endif
  return false
}

const sanitizeHeaderValue = (value: string): string => value.replace(/[\r\n]+/g, '').trim()

const messageFromPayload = (payload: unknown, fallback: string): string => {
  if (payload && typeof payload === 'object' && 'message' in payload) {
    const message = String((payload as { message?: string }).message || '').trim()
    if (message) {
      if (message.includes('New-Api-User')) {
        return '该站点需要数字用户 ID。请打开站点「个人设置」查看用户 ID，并与系统访问令牌一起填写。'
      }
      if (message.includes('access token 无效')) {
        return '系统访问令牌无效。请重新生成，不要使用 sk- 开头的模型调用 Key。'
      }
      const reason =
        'reason' in payload ? String((payload as { reason?: string }).reason || '') : ''
      if (reason === 'TURNSTILE_VERIFICATION_FAILED' || message.toLowerCase().includes('turnstile')) {
        return '需要完成 Cloudflare 人机验证。请在页面上完成验证后重试。'
      }
      return message
    }
  }
  return fallback
}

const headerValue = (header: Record<string, unknown> | undefined, name: string): string => {
  if (!header) {
    return ''
  }
  const lower = name.toLowerCase()
  for (const [key, value] of Object.entries(header)) {
    if (key.toLowerCase() !== lower) {
      continue
    }
    if (Array.isArray(value)) {
      return value.filter(Boolean).join('|||')
    }
    return value == null ? '' : String(value)
  }
  return ''
}

const cookiePair = (setCookie: string): string => {
  const pair = setCookie.split(';')[0]?.trim() || ''
  if (!pair.includes('=')) {
    return ''
  }
  const attributes = setCookie.toLowerCase()
  if (attributes.includes('max-age=0') || attributes.includes('max-age=-')) {
    return ''
  }
  return pair
}

export const mergeCookies = (...chunks: string[]): string => {
  const map = new Map<string, string>()
  for (const chunk of chunks) {
    for (const part of chunk.split('|||')) {
      const trimmed = part.trim()
      if (!trimmed) {
        continue
      }
      const pair = cookiePair(trimmed) || (trimmed.includes('=') && !trimmed.includes(';') ? trimmed : '')
      if (!pair) {
        continue
      }
      const eq = pair.indexOf('=')
      const name = pair.slice(0, eq).trim()
      const value = pair.slice(eq + 1)
      if (name) {
        map.set(name, value)
      }
    }
  }
  return [...map.entries()].map(([name, value]) => `${name}=${value}`).join('; ')
}

export const asCookieAuth = (cookieHeader: string): string => `${COOKIE_AUTH_PREFIX}${cookieHeader}`

const applyAuthHeaders = (
  header: Record<string, string>,
  token: string | undefined,
  cookie: string | undefined,
  useProxy: boolean
): void => {
  const cookieHeader =
    cookie?.trim() ||
    (token && token.startsWith(COOKIE_AUTH_PREFIX) && token !== NATIVE_COOKIE_AUTH
      ? token.slice(COOKIE_AUTH_PREFIX.length)
      : '')
  if (cookieHeader) {
    if (useProxy) {
      header['X-Yucon-Cookie'] = sanitizeHeaderValue(cookieHeader)
    } else {
      header.Cookie = sanitizeHeaderValue(cookieHeader)
    }
  }
  if (token && !token.startsWith(COOKIE_AUTH_PREFIX)) {
    header.Authorization = `Bearer ${sanitizeHeaderValue(token)}`
  }
}

const parsePayload = (payload: unknown): unknown => {
  if (typeof payload !== 'string') {
    return payload
  }
  try {
    return JSON.parse(payload) as unknown
  } catch {
    return payload
  }
}

const takeSidecarCookies = (payload: unknown): { data: unknown; cookies: string } => {
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return { data: payload, cookies: '' }
  }
  const record = payload as Record<string, unknown>
  const cookies = typeof record[YUCON_COOKIES_FIELD] === 'string' ? record[YUCON_COOKIES_FIELD] : ''
  if (YUCON_COOKIES_FIELD in record) {
    delete record[YUCON_COOKIES_FIELD]
  }
  return { data: payload, cookies }
}

export const requestJsonDetailed = async <T>(options: RequestOptions): Promise<RequestResult<T>> => {
  const method = options.method ?? 'GET'
  const target = joinUrl(options.baseUrl, options.path)
  const useProxy = shouldUseDevProxy()
  const header: Record<string, string> = {
    Accept: 'application/json'
  }
  if (options.data !== undefined && method !== 'GET') {
    header['Content-Type'] = 'application/json'
  }
  applyAuthHeaders(header, options.token, options.cookie, useProxy)
  if (options.userId) {
    header['New-Api-User'] = sanitizeHeaderValue(options.userId)
  }
  if (useProxy) {
    header['X-Yucon-Target'] = normalizeBaseUrl(options.baseUrl)
  }

  const path = options.path.startsWith('/') ? options.path : `/${options.path}`
  const url = useProxy
    ? `${typeof window !== 'undefined' ? window.location.origin : ''}${PROXY_PREFIX}${path}`
    : target

  return new Promise((resolve, reject) => {
    uni.request({
      url,
      method,
      header,
      data: options.data as string | Record<string, unknown> | undefined,
      timeout: options.timeout ?? 20000,
      success: (response) => {
        const status = response.statusCode ?? 0
        const parsed = parsePayload(response.data)
        const sidecar = takeSidecarCookies(parsed)
        const cookies = mergeCookies(
          headerValue(response.header as Record<string, unknown> | undefined, 'X-Yucon-Set-Cookie'),
          headerValue(response.header as Record<string, unknown> | undefined, 'Set-Cookie'),
          sidecar.cookies,
          ...(Array.isArray(response.cookies) ? response.cookies : [])
        )
        if (status === 204) {
          resolve({ data: {} as T, cookies, status })
          return
        }
        if (typeof sidecar.data === 'string') {
          reject(new ApiError(sidecar.data || `请求失败（${status}）`, status))
          return
        }
        if (status >= 400) {
          reject(new ApiError(messageFromPayload(sidecar.data, `请求失败（${status}）`), status))
          return
        }
        resolve({ data: (sidecar.data ?? {}) as T, cookies, status })
      },
      fail: (error) => {
        const raw = error.errMsg || '网络请求失败'
        if (raw.includes('timeout')) {
          reject(new ApiError('连接超时，请检查站点地址'))
          return
        }
        if (raw.toLowerCase().includes('cors') || raw.includes('Failed to fetch')) {
          reject(
            new ApiError(
              useProxy
                ? '开发代理请求被中断，请确认已使用 npm run dev:h5 预览'
                : '站点拒绝跨域请求。H5 预览请使用开发服务器，或改用 App 端'
            )
          )
          return
        }
        reject(new ApiError(raw.replace(/^request:fail\s*/i, '').trim() || '网络请求失败'))
      }
    })
  })
}

export const requestJson = async <T>(options: RequestOptions): Promise<T> => {
  const result = await requestJsonDetailed<T>(options)
  return result.data
}

export { normalizeBaseUrl }
