import { requestJson } from '@/utils/http'
import type { PlatformType } from '@/types/domain'

export interface DetectedSite {
  type: PlatformType
  siteName: string
  score: number
}

const asRecord = (value: unknown): Record<string, unknown> =>
  value && typeof value === 'object' ? (value as Record<string, unknown>) : {}

export const newApiStatusScore = (payload: Record<string, unknown>): number => {
  const nested = asRecord(payload.data)
  const data = Object.keys(nested).length ? nested : payload
  if (!Object.keys(data).length) {
    return 0
  }
  let score = 0
  if ('system_name' in data || 'SystemName' in data) score += 2
  if ('quota_per_unit' in data || 'QuotaPerUnit' in data) score += 2
  if ('email_verification' in data || 'EmailVerification' in data) score += 1
  if ('turnstile_check' in data || 'TurnstileCheck' in data) score += 1
  if ('github_oauth' in data || 'GitHubOAuth' in data) score += 1
  if ('google_oauth' in data || 'GoogleOAuth' in data) score += 1
  if ('version' in data && ('start_time' in data || 'StartTime' in data)) score += 2
  if (
    payload.success === true &&
    ('version' in data || 'system_name' in data || 'SystemName' in data)
  ) {
    score += 1
  }
  return score
}

export const sub2SettingsScore = (payload: Record<string, unknown>): number => {
  const nested = asRecord(payload.data)
  const data =
    'site_name' in nested || 'turnstile_enabled' in nested || 'turnstile_site_key' in nested
      ? nested
      : payload
  if (!Object.keys(data).length) {
    return 0
  }
  let score = 0
  if ('site_name' in data) score += 2
  if ('site_logo' in data || 'site_subtitle' in data) score += 1
  if ('turnstile_enabled' in data || 'turnstile_site_key' in data) score += 2
  if ('github_oauth_enabled' in data || 'google_oauth_enabled' in data) score += 2
  if ('email_verification_enabled' in data) score += 1
  if ('oidc_enabled' in data) score += 1
  return score
}

const detectNewApi = async (baseUrl: string): Promise<DetectedSite | null> => {
  try {
    const payload = await requestJson<Record<string, unknown>>({
      baseUrl,
      path: '/api/status'
    })
    if (!payload || typeof payload !== 'object') {
      return null
    }
    const score = newApiStatusScore(payload)
    if (score < 2) {
      return null
    }
    const data = asRecord(payload.data)
    return {
      type: 'newapi',
      siteName: String(data.system_name || data.SystemName || ''),
      score
    }
  } catch {
    return null
  }
}

const detectSub2 = async (baseUrl: string): Promise<DetectedSite | null> => {
  for (const path of ['/api/v1/settings/public', '/api/v1/public/settings']) {
    try {
      const payload = await requestJson<Record<string, unknown>>({
        baseUrl,
        path
      })
      if (!payload || typeof payload !== 'object') {
        continue
      }
      const score = sub2SettingsScore(payload)
      if (score < 2) {
        continue
      }
      const nested = asRecord(payload.data)
      const data =
        'site_name' in nested || 'turnstile_enabled' in nested ? nested : payload
      return {
        type: 'sub2api',
        siteName: String(data.site_name || ''),
        score
      }
    } catch {
      continue
    }
  }
  return null
}

export const detectSitePlatform = async (baseUrl: string): Promise<DetectedSite | null> => {
  const [newApi, sub2] = await Promise.all([detectNewApi(baseUrl), detectSub2(baseUrl)])
  if (!newApi) {
    return sub2
  }
  if (!sub2) {
    return newApi
  }
  return sub2.score > newApi.score ? sub2 : newApi
}
