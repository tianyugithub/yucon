import type { PlatformPreset, PlatformType } from '@/types/domain'

export const platformPresets: Record<PlatformType, PlatformPreset> = {
  newapi: {
    type: 'newapi',
    label: 'NewAPI',
    shortLabel: 'N',
    description: 'NewAPI 用户账号',
    color: '#fa2c19',
    lightColor: '#fff0ed',
    supportsAccessToken: true,
    supportsKeyModelLimits: true,
    supportsCrossGroupRetry: true,
    identityLabel: '用户名',
    identityPlaceholder: '站点用户名'
  },
  oneapi: {
    type: 'oneapi',
    label: 'OneAPI',
    shortLabel: 'O',
    description: 'OneAPI 用户账号',
    color: '#3178df',
    lightColor: '#edf4ff',
    supportsAccessToken: true,
    supportsKeyModelLimits: true,
    supportsCrossGroupRetry: true,
    identityLabel: '用户名',
    identityPlaceholder: '站点用户名'
  },
  sub2api: {
    type: 'sub2api',
    label: 'Sub2API',
    shortLabel: 'S',
    description: 'Sub2API 用户账号，使用邮箱密码登录；API Key 本身不限制模型，可用模型由分组决定',
    color: '#0d9488',
    lightColor: '#e7f7f4',
    supportsAccessToken: false,
    supportsKeyModelLimits: false,
    supportsCrossGroupRetry: false,
    identityLabel: '邮箱',
    identityPlaceholder: '登录邮箱'
  }
}

export const platformTypeOptions = Object.values(platformPresets)

export const platformLabelSlash = platformTypeOptions.map((preset) => preset.label).join(' / ')

export const getPlatformPreset = (type: string): PlatformPreset =>
  platformPresets[type as PlatformType] ?? platformPresets.newapi

export const summarizePlatformTypes = (accounts: Array<{ platformType: string }>): string => {
  const parts = platformTypeOptions
    .map((preset) => {
      const count = accounts.filter((account) => account.platformType === preset.type).length
      return count ? `${preset.label} ${count} 个` : ''
    })
    .filter(Boolean)
  return parts.join(' · ') || '暂无账号'
}
