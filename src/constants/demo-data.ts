import type {
  AccountDraft,
  ApiKeyDraft,
  PrototypeSettings
} from '@/types/domain'

export const defaultSettings: PrototypeSettings = {
  lowQuotaThreshold: 5,
  notificationEnabled: true,
  recordIpLog: false,
  darkMode: false
}

export const groupOptions = ['default', 'auto']
export const tagOptions = ['主号', '测试', '备用', '常用', '低额度']

export const createEmptyAccountDraft = (): AccountDraft => ({
  alias: '',
  siteName: '',
  baseUrl: '',
  platformType: 'newapi',
  authMode: 'password',
  username: '',
  password: '',
  accessToken: '',
  userId: '',
  tags: []
})

export const createEmptyApiKeyDraft = (accountId = ''): ApiKeyDraft => ({
  accountId,
  name: '',
  unlimitedQuota: true,
  remainQuota: '10',
  expiresAt: '',
  group: 'default',
  modelLimitsText: '',
  allowIpsText: '',
  crossGroupRetry: false
})
