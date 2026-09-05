import type { IncomingMessage, ServerResponse } from 'node:http'
import type { Plugin } from 'vite'

const PROXY_PREFIX = '/__yucon'
const YUCON_COOKIES_FIELD = '__yucon_cookies'

const HOP_BY_HOP = new Set([
  'connection',
  'content-encoding',
  'content-length',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'access-control-allow-origin',
  'access-control-allow-credentials',
  'access-control-allow-headers',
  'access-control-allow-methods',
  'access-control-expose-headers',
  'access-control-max-age',
  'location',
  'set-cookie',
  'cookie'
])

const readBody = (req: IncomingMessage): Promise<Buffer> =>
  new Promise((resolve, reject) => {
    const chunks: Buffer[] = []
    req.on('data', (chunk) => {
      chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk))
    })
    req.on('end', () => resolve(Buffer.concat(chunks)))
    req.on('error', reject)
  })

const isAllowedTarget = (value: string): boolean => {
  try {
    const url = new URL(value)
    return url.protocol === 'http:' || url.protocol === 'https:'
  } catch {
    return false
  }
}

const writeJson = (res: ServerResponse, status: number, payload: unknown): void => {
  if (res.headersSent) {
    res.end()
    return
  }
  res.statusCode = status
  res.setHeader('Content-Type', 'application/json; charset=utf-8')
  res.end(JSON.stringify(payload))
}

const handleProxy = async (req: IncomingMessage, res: ServerResponse): Promise<void> => {
  if (req.method === 'OPTIONS') {
    res.statusCode = 204
    res.end()
    return
  }

  const targetHeader = req.headers['x-yucon-target']
  const targetBase = Array.isArray(targetHeader) ? targetHeader[0] : targetHeader
  if (!targetBase || !isAllowedTarget(targetBase)) {
    writeJson(res, 400, { success: false, message: '无效的站点地址' })
    return
  }

  const incomingUrl = req.url ?? '/'
  const suffix = incomingUrl.startsWith(PROXY_PREFIX)
    ? incomingUrl.slice(PROXY_PREFIX.length) || '/'
    : incomingUrl
  const upstream = new URL(suffix, targetBase.endsWith('/') ? targetBase : `${targetBase}/`)
  const body = req.method && ['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)
    ? await readBody(req)
    : undefined

  const headers = new Headers()
  for (const [key, value] of Object.entries(req.headers)) {
    if (!value || Array.isArray(value)) {
      continue
    }
    const lower = key.toLowerCase()
    if (
      HOP_BY_HOP.has(lower) ||
      ['host', 'origin', 'referer', 'x-yucon-target', 'x-yucon-cookie'].includes(lower)
    ) {
      continue
    }
    headers.set(key, value)
  }

  const sessionCookie = req.headers['x-yucon-cookie']
  if (typeof sessionCookie === 'string' && sessionCookie.trim()) {
    headers.set('Cookie', sessionCookie.trim())
  }

  const response = await fetch(upstream, {
    method: req.method,
    headers,
    body: body && body.length ? body : undefined,
    redirect: 'follow'
  })

  const payload = Buffer.from(await response.arrayBuffer())
  const setCookies = (
    typeof response.headers.getSetCookie === 'function'
      ? response.headers.getSetCookie()
      : [response.headers.get('set-cookie')].filter((value): value is string => Boolean(value))
  )
    .map((value) => value.replace(/[\r\n]+/g, '').trim())
    .filter(Boolean)

  const responseBody = attachCookiesToJson(payload, setCookies)

  res.statusCode = response.status
  response.headers.forEach((value, key) => {
    if (HOP_BY_HOP.has(key.toLowerCase())) {
      return
    }
    res.setHeader(key, value)
  })
  if (setCookies.length) {
    res.setHeader('X-Yucon-Set-Cookie', setCookies.join('|||'))
  }
  res.setHeader('Content-Length', String(responseBody.length))
  res.end(responseBody)
}

const attachCookiesToJson = (payload: Buffer, cookies: string[]): Buffer => {
  if (!cookies.length) {
    return payload
  }
  try {
    const parsed = JSON.parse(payload.toString('utf8')) as unknown
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      return payload
    }
    return Buffer.from(
      JSON.stringify({
        ...(parsed as Record<string, unknown>),
        [YUCON_COOKIES_FIELD]: cookies.join('|||')
      })
    )
  } catch {
    return payload
  }
}

export const yuconProxyPlugin = (): Plugin => ({
  name: 'yucon-proxy',
  configureServer(server) {
    server.middlewares.use(async (req, res, next) => {
      if (!req.url?.startsWith(`${PROXY_PREFIX}/`) && req.url !== PROXY_PREFIX) {
        next()
        return
      }
      try {
        await handleProxy(req, res)
      } catch (error) {
        writeJson(res, 502, {
          success: false,
          message: error instanceof Error ? error.message : '代理请求失败'
        })
      }
    })
  }
})
