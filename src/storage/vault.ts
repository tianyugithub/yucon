import type {
  Account,
  AccountSession,
  ApiKey,
  CheckinLog,
  PrototypeSettings,
  UsageLog
} from '@/types/domain'

const KEYS = {
  accounts: 'yucon.v2.accounts',
  sessions: 'yucon.v2.sessions',
  apiKeys: 'yucon.v2.apiKeys',
  checkins: 'yucon.v2.checkinLogs',
  usage: 'yucon.v2.usageLogs',
  settings: 'yucon.v2.settings',
  revealed: 'yucon.v2.revealedKeys'
} as const

const readJson = <T>(key: string, fallback: T): T => {
  try {
    const raw = uni.getStorageSync(key)
    if (!raw) {
      return fallback
    }
    return typeof raw === 'string' ? (JSON.parse(raw) as T) : (raw as T)
  } catch {
    return fallback
  }
}

const writeJson = (key: string, value: unknown): void => {
  uni.setStorageSync(key, JSON.stringify(value))
}

export const loadAccounts = (): Account[] => readJson(KEYS.accounts, [])
export const saveAccounts = (accounts: Account[]): void => writeJson(KEYS.accounts, accounts)

export const loadSessions = (): AccountSession[] => readJson(KEYS.sessions, [])
export const saveSessions = (sessions: AccountSession[]): void => writeJson(KEYS.sessions, sessions)

export const loadApiKeys = (): ApiKey[] => readJson(KEYS.apiKeys, [])
export const saveApiKeys = (apiKeys: ApiKey[]): void => writeJson(KEYS.apiKeys, apiKeys)

export const loadCheckinLogs = (): CheckinLog[] => readJson(KEYS.checkins, [])
export const saveCheckinLogs = (logs: CheckinLog[]): void => writeJson(KEYS.checkins, logs)

export const loadUsageLogs = (): UsageLog[] => readJson(KEYS.usage, [])
export const saveUsageLogs = (logs: UsageLog[]): void => writeJson(KEYS.usage, logs)

export const loadSettings = (): Partial<PrototypeSettings> => readJson(KEYS.settings, {})
export const saveSettings = (settings: PrototypeSettings): void => writeJson(KEYS.settings, settings)

export const loadRevealedKeys = (): Record<string, string> => readJson(KEYS.revealed, {})
export const saveRevealedKeys = (keys: Record<string, string>): void => writeJson(KEYS.revealed, keys)
