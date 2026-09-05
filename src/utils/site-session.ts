import { Capacitor, registerPlugin } from '@capacitor/core'
import { normalizeBaseUrl } from '@/utils/http'

interface SiteSessionPlugin {
  capture(options: { loginUrl: string; email?: string; password?: string }): Promise<{
    accessToken: string
    refreshToken?: string
  }>
}

const SiteSession = registerPlugin<SiteSessionPlugin>('SiteSession')

export const canCaptureSiteSession = (): boolean =>
  Capacitor.isNativePlatform() && Capacitor.getPlatform() === 'android'

export const captureSiteSession = async (options: {
  baseUrl: string
  email?: string
  password?: string
}): Promise<{ accessToken: string; refreshToken: string }> => {
  if (!canCaptureSiteSession()) {
    throw new Error('当前环境无法打开站点登录页')
  }
  const loginUrl = `${normalizeBaseUrl(options.baseUrl)}/login`
  const result = await SiteSession.capture({
    loginUrl,
    email: options.email?.trim() || '',
    password: options.password || ''
  })
  const accessToken = result.accessToken?.trim() || ''
  if (!accessToken) {
    throw new Error('未能从站点获取登录令牌')
  }
  return {
    accessToken,
    refreshToken: result.refreshToken?.trim() || ''
  }
}
