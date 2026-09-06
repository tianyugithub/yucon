export type PlatformType = 'newapi' | 'sub2api'

export type AccountStatus = 'active' | 'low' | 'disabled' | 'pending' | 'expired'

export type ApiKeyStatus = 'enabled' | 'disabled' | 'expired' | 'exhausted'

export type FeedbackType = 'text' | 'success' | 'error' | 'warning' | 'loading'

export type AuthMode = 'password' | 'access_token'

export interface PlatformPreset {
  type: PlatformType
  label: string
  shortLabel: string
  description: string
  color: string
  lightColor: string
  supportsAccessToken: boolean
  supportsKeyModelLimits: boolean
  supportsCrossGroupRetry: boolean
  identityLabel: string
  identityPlaceholder: string
  iconAsset: string
}

export interface BalancePoint {
  label: string
  value: number
}

export interface Account {
  id: string
  alias: string
  siteName: string
  baseUrl: string
  platformType: PlatformType
  authMode: AuthMode
  userId: string
  username: string
  displayName: string
  email: string
  group: string
  quota: number
  usedQuota: number
  requestCount: number
  quotaPerUnit: number
  status: AccountStatus
  lastCheckin: string | null
  checkedInToday: boolean
  checkinEnabled: boolean
  tags: string[]
  trend: BalancePoint[]
  lastSyncedAt: string | null
  lastError: string | null
  createdAt: string
  updatedAt: string
}

export interface AccountSession {
  accountId: string
  accessToken: string
  userId: string
  refreshToken?: string
}

export interface ApiKey {
  id: string
  accountId: string
  remoteId: number
  name: string
  key: string
  keyMasked: boolean
  status: ApiKeyStatus
  remainQuota: number
  usedQuota: number
  unlimitedQuota: boolean
  expiresAt: string | null
  createdAt: string
  accessedAt: string | null
  group: string
  modelLimits: string[]
  allowIps: string[]
  crossGroupRetry: boolean
}

export interface CheckinLog {
  id: string
  accountId: string
  platformType: PlatformType
  time: string
  success: boolean
  message: string
  reward?: number
}

export interface UsageLog {
  id: string
  accountId: string
  platformType: PlatformType
  apiKeyId: string
  apiKeyName: string
  model: string
  time: string
  quotaCost: number
  promptTokens: number
  completionTokens: number
  success: boolean
}

export interface PrototypeSettings {
  lowQuotaThreshold: number
  notificationEnabled: boolean
  recordIpLog: boolean
  darkMode: boolean
}

export interface FeedbackState {
  visible: boolean
  message: string
  type: FeedbackType
}

export interface AccountDraft {
  id?: string
  alias: string
  siteName: string
  baseUrl: string
  platformType: PlatformType
  authMode: AuthMode
  username: string
  password: string
  accessToken: string
  refreshToken?: string
  userId: string
  tags: string[]
  turnstileToken?: string
}

export interface ApiKeyDraft {
  id?: string
  accountId: string
  name: string
  unlimitedQuota: boolean
  remainQuota: string
  expiresAt: string
  group: string
  modelLimitsText: string
  allowIpsText: string
  crossGroupRetry: boolean
}

export interface TokenGroupOption {
  name: string
  desc: string
  ratio: number | null
  ratioLabel: string
  remoteId?: number
}
