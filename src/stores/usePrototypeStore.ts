import { computed, reactive, ref } from 'vue'
import { defineStore } from 'pinia'
import {
  connectAccount,
  createToken,
  deleteToken,
  doCheckin,
  fetchCheckinStatus,
  fetchCurrentUser,
  fetchGroupModels,
  fetchTokens,
  fetchUsageLogs,
  fetchUserGroups,
  revealTokenKey,
  updateToken,
  type NewApiToken,
  type NewApiUsageLog,
  type NewApiUser
} from '@/api/newapi'
import {
  connectSub2Account,
  createSub2Key,
  deleteSub2Key,
  fetchCurrentSub2User,
  fetchSub2DashboardStats,
  fetchSub2Groups,
  fetchSub2KeyById,
  fetchSub2Keys,
  fetchSub2UsageLogs,
  refreshSub2Token,
  updateSub2Key,
  type Sub2Key,
  type Sub2UsageLog,
  type Sub2User
} from '@/api/sub2api'
import {
  createEmptyAccountDraft,
  createEmptyApiKeyDraft,
  defaultSettings
} from '@/constants/demo-data'
import { getPlatformPreset } from '@/constants/platform-presets'
import {
  loadAccounts,
  loadApiKeys,
  loadCheckinLogs,
  loadRevealedKeys,
  loadSessions,
  loadSettings,
  loadUsageLogs,
  saveAccounts,
  saveApiKeys,
  saveCheckinLogs,
  saveRevealedKeys,
  saveSessions,
  saveSettings,
  saveUsageLogs
} from '@/storage/vault'
import type {
  Account,
  AccountDraft,
  AccountSession,
  AccountStatus,
  ApiKey,
  ApiKeyDraft,
  ApiKeyStatus,
  CheckinLog,
  FeedbackState,
  FeedbackType,
  PrototypeSettings,
  TokenGroupOption,
  UsageLog
} from '@/types/domain'
import { ApiError, isAuthExpiredError, normalizeBaseUrl } from '@/utils/http'
import { canCaptureSiteSession, captureSiteSession } from '@/utils/site-session'
import {
  dateInputToUnix,
  quotaToMoney,
  roundMoney,
  unixToIso,
  weekdayLabel
} from '@/utils/quota'

const TOKEN_STATUS: Record<number, ApiKeyStatus> = {
  1: 'enabled',
  2: 'disabled',
  3: 'expired',
  4: 'exhausted'
}

const SUB2_KEY_STATUS: Record<string, ApiKeyStatus> = {
  active: 'enabled',
  inactive: 'disabled',
  expired: 'expired',
  quota_exhausted: 'exhausted'
}

const SUB2_QUOTA_PER_UNIT = 1
const SESSION_EXPIRED_MESSAGE = '登录已过期，请重新登录'

const localDateKey = (iso: string): string => {
  const date = new Date(iso)
  return `${date.getFullYear()}-${date.getMonth() + 1}-${date.getDate()}`
}

const isoNow = (): string => new Date().toISOString()

const hostnameOf = (baseUrl: string): string => {
  try {
    return new URL(normalizeBaseUrl(baseUrl)).hostname
  } catch {
    return baseUrl.replace(/^https?:\/\//, '').replace(/\/$/, '') || '未命名站点'
  }
}

const splitList = (value: string): string[] =>
  value
    .split(/[\n,，]/)
    .map((item) => item.trim())
    .filter(Boolean)

const isMaskedKey = (value?: string): boolean =>
  !value || value.includes('*') || value.includes('•') || value.includes('·')

export const usePrototypeStore = defineStore('prototype', () => {
  const accounts = ref<Account[]>([])
  const sessions = ref<AccountSession[]>([])
  const apiKeys = ref<ApiKey[]>([])
  const checkinLogs = ref<CheckinLog[]>([])
  const usageLogs = ref<UsageLog[]>([])
  const revealedKeys = ref<Record<string, string>>({})
  const settings = reactive<PrototypeSettings>({ ...defaultSettings })
  const feedback = reactive<FeedbackState>({
    visible: false,
    message: '',
    type: 'text'
  })
  const searchTerm = ref('')
  const selectedAccountStatus = ref<'all' | AccountStatus>('all')
  const selectedAccountId = ref<string | null>(null)
  const selectedKeyId = ref<string | null>(null)
  const isRefreshing = ref(false)
  const tokenGroups = ref<Record<string, TokenGroupOption[]>>({})
  const tokenModels = ref<Record<string, string[]>>({})
  const hydrated = ref(false)
  const actionCounter = ref(0)
  let feedbackTimer: ReturnType<typeof setTimeout> | undefined

  const persist = (): void => {
    saveAccounts(accounts.value)
    saveSessions(sessions.value)
    saveApiKeys(apiKeys.value)
    saveCheckinLogs(checkinLogs.value)
    saveUsageLogs(usageLogs.value)
    saveSettings(settings)
    saveRevealedKeys(revealedKeys.value)
  }

  const accountById = (id: string): Account | undefined =>
    accounts.value.find((account) => account.id === id)

  const sessionByAccount = (accountId: string): AccountSession | undefined =>
    sessions.value.find((session) => session.accountId === accountId)

  const apiKeyById = (id: string): ApiKey | undefined =>
    apiKeys.value.find((apiKey) => apiKey.id === id)

  const apiKeysForAccount = (accountId: string): ApiKey[] =>
    apiKeys.value.filter((apiKey) => apiKey.accountId === accountId)

  const displayAccountName = (account: Account): string =>
    account.alias || account.displayName || account.username || '未命名账号'

  const accountTypeLabel = (account: Account): string =>
    getPlatformPreset(account.platformType).label

  const filteredAccounts = computed(() => {
    const keyword = searchTerm.value.trim().toLowerCase()
    return accounts.value.filter((account) => {
      const matchesKeyword =
        !keyword ||
        displayAccountName(account).toLowerCase().includes(keyword) ||
        account.siteName.toLowerCase().includes(keyword) ||
        account.username.toLowerCase().includes(keyword) ||
        account.baseUrl.toLowerCase().includes(keyword) ||
        accountTypeLabel(account).toLowerCase().includes(keyword)
      const matchesStatus =
        selectedAccountStatus.value === 'all' || account.status === selectedAccountStatus.value
      return matchesKeyword && matchesStatus
    })
  })

  const totalQuota = computed(() =>
    roundMoney(accounts.value.reduce((sum, account) => sum + account.quota, 0))
  )
  const totalUsedQuota = computed(() =>
    roundMoney(accounts.value.reduce((sum, account) => sum + account.usedQuota, 0))
  )
  const totalRequestCount = computed(() =>
    accounts.value.reduce((sum, account) => sum + account.requestCount, 0)
  )
  const todayUsage = computed(() => {
    const today = localDateKey(isoNow())
    return roundMoney(
      usageLogs.value
        .filter((log) => localDateKey(log.time) === today)
        .reduce((sum, log) => sum + log.quotaCost, 0)
    )
  })
  const isCheckinEligible = (account: Account): boolean =>
    account.platformType !== 'sub2api' &&
    account.checkinEnabled &&
    account.status !== 'disabled' &&
    account.status !== 'pending' &&
    account.status !== 'expired'

  const todayCheckinStatus = computed(() => {
    const eligible = accounts.value.filter((account) => isCheckinEligible(account))
    return {
      done: eligible.filter((account) => account.checkedInToday).length,
      total: eligible.length
    }
  })
  const expiredAccounts = computed(() =>
    accounts.value.filter((account) => account.status === 'expired')
  )
  const lowQuotaAccounts = computed(() =>
    accounts.value.filter(
      (account) =>
        account.status !== 'disabled' &&
        account.status !== 'pending' &&
        account.status !== 'expired' &&
        account.quota < settings.lowQuotaThreshold
    )
  )
  const activeApiKeyCount = computed(
    () => apiKeys.value.filter((apiKey) => apiKey.status === 'enabled').length
  )

  const keyCountForAccount = (accountId: string): number => apiKeysForAccount(accountId).length
  const isCheckedInToday = (account: Account): boolean =>
    isCheckinEligible(account) && account.checkedInToday
  const fallbackGroups = (account?: Account): TokenGroupOption[] => {
    const names = new Set(['default'])
    if (account?.group) {
      names.add(account.group)
    }
    names.add('auto')
    return [...names].map((name) => ({
      name,
      desc: name === 'auto' ? '按系统自动分组规则路由' : name === 'default' ? '默认分组' : '账号分组',
      ratio: name === 'auto' ? null : 1,
      ratioLabel: name === 'auto' ? '自动' : '×1'
    }))
  }

  const groupsForAccount = (account?: Account): TokenGroupOption[] => {
    if (!account) {
      return []
    }
    return tokenGroups.value[account.id] ?? fallbackGroups(account)
  }

  const tokenGroupLabel = (accountId: string, groupName: string): string => {
    const option = groupsForAccount(accountById(accountId)).find((group) => group.name === groupName)
    if (!option) {
      return groupName || 'default'
    }
    return `${option.name} · ${option.ratioLabel}`
  }

  const defaultGroupForAccount = (account?: Account): string => {
    const groups = groupsForAccount(account)
    if (groups.some((group) => group.name === 'auto')) {
      return 'auto'
    }
    if (account?.group && groups.some((group) => group.name === account.group)) {
      return account.group
    }
    return groups[0]?.name || 'default'
  }

  const modelsForGroup = (accountId: string, group: string): string[] =>
    tokenModels.value[`${accountId}:${group || 'all'}`] ?? []

  const loadTokenGroups = async (accountId: string): Promise<TokenGroupOption[]> => {
    const account = accountById(accountId)
    if (!account) {
      return []
    }
    try {
      const groups = await withAccountAuth(account, async (session) =>
        account.platformType === 'sub2api'
          ? await fetchSub2Groups(account.baseUrl, session.accessToken)
          : await fetchUserGroups(account.baseUrl, session.accessToken, session.userId)
      )
      tokenGroups.value[accountId] = groups.length ? groups : fallbackGroups(account)
    } catch (error) {
      tokenGroups.value[accountId] = fallbackGroups(account)
      if (isAuthExpiredError(error)) {
        throw error
      }
    }
    return tokenGroups.value[accountId]
  }

  const loadGroupModels = async (accountId: string, group: string): Promise<string[]> => {
    const account = accountById(accountId)
    const cacheKey = `${accountId}:${group || 'all'}`
    if (!account) {
      return []
    }
    if (account.platformType === 'sub2api') {
      tokenModels.value[cacheKey] = []
      return []
    }
    try {
      tokenModels.value[cacheKey] = await withAccountAuth(account, async (session) =>
        fetchGroupModels(account.baseUrl, session.accessToken, session.userId, group)
      )
    } catch (error) {
      tokenModels.value[cacheKey] = tokenModels.value[cacheKey] ?? []
      if (isAuthExpiredError(error)) {
        throw error
      }
    }
    return tokenModels.value[cacheKey] ?? []
  }

  const makeId = (prefix: string): string => {
    actionCounter.value += 1
    return `${prefix}-${Date.now()}-${actionCounter.value}`
  }

  const updateAccountStatus = (account: Account): void => {
    if (account.status === 'pending' || account.status === 'disabled' || account.status === 'expired') {
      return
    }
    account.status = account.quota < settings.lowQuotaThreshold ? 'low' : 'active'
  }

  const appendTrendPoint = (account: Account): void => {
    const now = isoNow()
    const label = weekdayLabel(now)
    const point = { label, value: account.quota }
    const last = account.trend[account.trend.length - 1]
    if (last && localDateKey(account.updatedAt) === localDateKey(now)) {
      account.trend = [...account.trend.slice(0, -1), point]
      return
    }
    account.trend = [...account.trend.slice(-6), point]
  }

  const applyUserSnapshot = (account: Account, user: NewApiUser): void => {
    account.userId = String(user.id)
    account.username = user.username || account.username
    account.displayName = user.display_name || account.displayName
    account.email = user.email || ''
    account.group = user.group || 'default'
    account.quota = quotaToMoney(user.quota ?? 0, account.quotaPerUnit)
    account.usedQuota = quotaToMoney(user.used_quota ?? 0, account.quotaPerUnit)
    account.requestCount = user.request_count ?? 0
    account.updatedAt = isoNow()
    account.lastSyncedAt = account.updatedAt
    account.lastError = null
    if (user.status !== undefined && user.status !== 1) {
      account.status = 'disabled'
      return
    }
    account.status = 'active'
    appendTrendPoint(account)
    updateAccountStatus(account)
  }

  const mapToken = (account: Account, token: NewApiToken): ApiKey => {
    const id = `${account.id}:${token.id}`
    const revealed = revealedKeys.value[id]
    const rawKey = revealed || token.key || ''
    const expiredAt = token.expired_time && token.expired_time > 0 ? unixToIso(token.expired_time) : null
    return {
      id,
      accountId: account.id,
      remoteId: token.id,
      name: token.name || '未命名 Key',
      key: rawKey,
      keyMasked: !revealed && isMaskedKey(rawKey),
      status: TOKEN_STATUS[token.status ?? 1] ?? 'enabled',
      remainQuota: quotaToMoney(token.remain_quota ?? 0, account.quotaPerUnit),
      usedQuota: quotaToMoney(token.used_quota ?? 0, account.quotaPerUnit),
      unlimitedQuota: Boolean(token.unlimited_quota),
      expiresAt: expiredAt,
      createdAt: unixToIso(token.created_time) || isoNow(),
      accessedAt: unixToIso(token.accessed_time),
      group: token.group || 'default',
      modelLimits: token.model_limits
        ? token.model_limits.split(',').map((item) => item.trim()).filter(Boolean)
        : [],
      allowIps: token.allow_ips
        ? token.allow_ips.split(/[\n,]/).map((item) => item.trim()).filter(Boolean)
        : [],
      crossGroupRetry: Boolean(token.cross_group_retry)
    }
  }

  const mapSub2Key = (account: Account, token: Sub2Key): ApiKey => {
    const id = `${account.id}:${token.id}`
    const revealed = revealedKeys.value[id]
    const rawKey = revealed || token.key || ''
    const quota = Number(token.quota ?? 0)
    const used = Number(token.quota_used ?? 0)
    const unlimited = !Number.isFinite(quota) || quota <= 0
    return {
      id,
      accountId: account.id,
      remoteId: token.id,
      name: token.name || '未命名 Key',
      key: rawKey,
      keyMasked: !revealed && isMaskedKey(rawKey),
      status: SUB2_KEY_STATUS[token.status ?? 'active'] ?? 'enabled',
      remainQuota: unlimited ? 0 : roundMoney(Math.max(0, quota - used)),
      usedQuota: roundMoney(used),
      unlimitedQuota: unlimited,
      expiresAt: token.expires_at || null,
      createdAt: token.created_at || isoNow(),
      accessedAt: token.last_used_at || null,
      group: token.group?.name || (token.group_id ? String(token.group_id) : defaultGroupForAccount(account)),
      modelLimits: [],
      allowIps: Array.isArray(token.ip_whitelist) ? token.ip_whitelist.filter(Boolean) : [],
      crossGroupRetry: false
    }
  }

  const applySub2UserSnapshot = (account: Account, user: Sub2User, usedQuota?: number, requestCount?: number): void => {
    account.userId = String(user.id)
    account.username = user.username || account.username
    account.displayName = user.username || account.displayName
    account.email = user.email || account.email
    account.quotaPerUnit = SUB2_QUOTA_PER_UNIT
    account.quota = roundMoney(user.balance ?? 0)
    account.usedQuota = roundMoney(usedQuota ?? account.usedQuota)
    account.requestCount = requestCount ?? account.requestCount
    account.checkinEnabled = false
    account.checkedInToday = false
    account.updatedAt = isoNow()
    account.lastSyncedAt = account.updatedAt
    account.lastError = null
    if (user.status && user.status !== 'active') {
      account.status = 'disabled'
      return
    }
    account.status = 'active'
    appendTrendPoint(account)
    updateAccountStatus(account)
  }

  const mergeSub2UsageLogs = (account: Account, logs: Sub2UsageLog[]): void => {
    const mapped = logs.map((log) => {
      const time = log.created_at || isoNow()
      return {
        id: `${account.id}:usage:${log.id ?? time}`,
        accountId: account.id,
        platformType: account.platformType,
        apiKeyId: log.api_key_id ? `${account.id}:${log.api_key_id}` : '',
        apiKeyName: log.api_key?.name || '未命名 Key',
        model: log.model || '未知模型',
        time,
        quotaCost: roundMoney(log.actual_cost ?? log.total_cost ?? 0),
        promptTokens: log.input_tokens ?? 0,
        completionTokens: log.output_tokens ?? 0,
        success: true
      } satisfies UsageLog
    })
    const others = usageLogs.value.filter((item) => item.accountId !== account.id)
    usageLogs.value = [...mapped, ...others]
      .sort((left, right) => new Date(right.time).getTime() - new Date(left.time).getTime())
      .slice(0, 100)
  }

  const refreshSub2Session = async (account: Account, session: AccountSession): Promise<AccountSession> => {
    if (!session.refreshToken) {
      throw new ApiError(SESSION_EXPIRED_MESSAGE, 401)
    }
    const tokens = await refreshSub2Token(account.baseUrl, session.refreshToken)
    session.accessToken = tokens.access_token
    if (tokens.refresh_token) {
      session.refreshToken = tokens.refresh_token
    }
    persist()
    return session
  }

  const markSessionExpired = (account: Account): void => {
    account.status = 'expired'
    account.lastError = SESSION_EXPIRED_MESSAGE
    persist()
  }

  const withAccountAuth = async <T>(
    account: Account,
    run: (session: AccountSession) => Promise<T>
  ): Promise<T> => {
    const session = sessionByAccount(account.id)
    if (!session) {
      markSessionExpired(account)
      throw new ApiError(SESSION_EXPIRED_MESSAGE, 401)
    }
    try {
      return await run(session)
    } catch (error) {
      if (!isAuthExpiredError(error)) {
        throw error
      }
      if (account.platformType === 'sub2api' && session.refreshToken) {
        try {
          const nextSession = await refreshSub2Session(account, session)
          return await run(nextSession)
        } catch {
          markSessionExpired(account)
          throw new ApiError(SESSION_EXPIRED_MESSAGE, 401)
        }
      }
      markSessionExpired(account)
      throw new ApiError(SESSION_EXPIRED_MESSAGE, 401)
    }
  }

  const replaceAccountKeys = (accountId: string, nextKeys: ApiKey[]): void => {
    apiKeys.value = [...apiKeys.value.filter((item) => item.accountId !== accountId), ...nextKeys]
  }

  const mergeUsageLogs = (account: Account, logs: NewApiUsageLog[]): void => {
    const mapped = logs.map((log) => {
      const time = unixToIso(log.created_at) || isoNow()
      return {
        id: `${account.id}:usage:${log.id ?? time}`,
        accountId: account.id,
        platformType: account.platformType,
        apiKeyId: '',
        apiKeyName: log.token_name || '未命名 Key',
        model: log.model_name || '未知模型',
        time,
        quotaCost: quotaToMoney(log.quota ?? 0, account.quotaPerUnit),
        promptTokens: log.prompt_tokens ?? 0,
        completionTokens: log.completion_tokens ?? 0,
        success: (log.type ?? 2) !== 5
      } satisfies UsageLog
    })
    const others = usageLogs.value.filter((item) => item.accountId !== account.id)
    usageLogs.value = [...mapped, ...others]
      .sort((left, right) => new Date(right.time).getTime() - new Date(left.time).getTime())
      .slice(0, 100)
  }

  const mergeCheckinLogs = (account: Account, records: Array<{ checkin_date: string; quota_awarded: number }>): void => {
    const mapped = records.map((record) => {
      const time = new Date(`${record.checkin_date}T09:00:00`).toISOString()
      return {
        id: `${account.id}:checkin:${record.checkin_date}`,
        accountId: account.id,
        platformType: account.platformType,
        time,
        success: true,
        message: `签到成功，获得 ${quotaToMoney(record.quota_awarded, account.quotaPerUnit).toFixed(2)} 额度`,
        reward: quotaToMoney(record.quota_awarded, account.quotaPerUnit)
      } satisfies CheckinLog
    })
    const others = checkinLogs.value.filter((item) => item.accountId !== account.id)
    checkinLogs.value = [...mapped, ...others]
      .sort((left, right) => new Date(right.time).getTime() - new Date(left.time).getTime())
      .slice(0, 100)
  }

  const syncSub2Account = async (account: Account): Promise<Account> =>
    withAccountAuth(account, async (activeSession) => {
      const user = await fetchCurrentSub2User(account.baseUrl, activeSession.accessToken)
      activeSession.userId = String(user.id)
      const [tokens, logs, stats] = await Promise.all([
        fetchSub2Keys(account.baseUrl, activeSession.accessToken),
        fetchSub2UsageLogs(account.baseUrl, activeSession.accessToken),
        fetchSub2DashboardStats(account.baseUrl, activeSession.accessToken)
      ])
      applySub2UserSnapshot(account, user, stats?.total_actual_cost, stats?.total_requests)
      replaceAccountKeys(account.id, tokens.map((token) => mapSub2Key(account, token)))
      mergeSub2UsageLogs(account, logs)
      persist()
      return account
    })

  const syncAccount = async (accountId: string): Promise<Account> => {
    const account = accountById(accountId)
    if (!account) {
      throw new ApiError('账号不存在')
    }
    try {
      if (account.platformType === 'sub2api') {
        return await syncSub2Account(account)
      }
      return await withAccountAuth(account, async (session) => {
        const user = await fetchCurrentUser(account.baseUrl, session.accessToken, session.userId)
        session.userId = String(user.id)
        applyUserSnapshot(account, user)
        const [tokens, logs, checkin] = await Promise.all([
          fetchTokens(account.baseUrl, session.accessToken, session.userId),
          fetchUsageLogs(account.baseUrl, session.accessToken, session.userId),
          fetchCheckinStatus(account.baseUrl, session.accessToken, session.userId)
        ])
        replaceAccountKeys(account.id, tokens.map((token) => mapToken(account, token)))
        mergeUsageLogs(account, logs)
        const stats = checkin?.stats ?? checkin
        if (checkin) {
          account.checkinEnabled = checkin.enabled !== false
        }
        if (!account.checkinEnabled) {
          account.checkedInToday = false
        } else if (stats) {
          account.checkedInToday = Boolean(stats.checked_in_today)
        }
        const records = stats?.records ?? []
        if (records.length) {
          const latest = records[0]
          account.lastCheckin = latest ? new Date(`${latest.checkin_date}T09:00:00`).toISOString() : account.lastCheckin
          mergeCheckinLogs(account, records)
        }
        persist()
        return account
      })
    } catch (error) {
      if (account.status !== 'expired') {
        account.lastError = error instanceof Error ? error.message : '同步失败'
        account.status = account.userId ? account.status : 'pending'
        persist()
      }
      throw error
    }
  }

  const hydrate = (): void => {
    if (hydrated.value) {
      return
    }
    const liveAccounts = loadAccounts().filter((account) => Boolean(account.baseUrl?.trim()))
    const liveIds = new Set(liveAccounts.map((account) => account.id))
    accounts.value = liveAccounts
    sessions.value = loadSessions().filter(
      (session) => liveIds.has(session.accountId) && Boolean(session.accessToken)
    )
    apiKeys.value = loadApiKeys().filter(
      (apiKey) => liveIds.has(apiKey.accountId) && Number.isFinite(apiKey.remoteId)
    )
    checkinLogs.value = loadCheckinLogs().filter((log) => liveIds.has(log.accountId))
    usageLogs.value = loadUsageLogs().filter((log) => liveIds.has(log.accountId))
    revealedKeys.value = Object.fromEntries(
      Object.entries(loadRevealedKeys()).filter(([id]) =>
        apiKeys.value.some((apiKey) => apiKey.id === id)
      )
    )
    Object.assign(settings, loadSettings())
    for (const account of accounts.value) {
      if (account.platformType === 'sub2api') {
        account.checkinEnabled = false
        account.checkedInToday = false
      }
      if (account.status === 'disabled' || account.status === 'pending') {
        continue
      }
      if (account.lastError === SESSION_EXPIRED_MESSAGE) {
        account.status = 'expired'
      }
    }
    hydrated.value = true
  }

  const refreshAllAccounts = async (): Promise<boolean> => {
    if (isRefreshing.value) {
      return false
    }
    isRefreshing.value = true
    try {
      await Promise.allSettled(
        accounts.value
          .filter((account) => {
            if (account.status === 'disabled' || account.status === 'pending') {
              return false
            }
            return Boolean(sessionByAccount(account.id))
          })
          .map((account) => syncAccount(account.id))
      )
      return true
    } finally {
      isRefreshing.value = false
    }
  }

  const checkinAccount = async (accountId: string): Promise<CheckinLog | null> => {
    const account = accountById(accountId)
    if (!account) {
      return null
    }
    if (account.status === 'disabled' || account.status === 'pending' || account.status === 'expired') {
      return {
        id: makeId('checkin-skip'),
        accountId: account.id,
        platformType: account.platformType,
        time: isoNow(),
        success: false,
        message:
          account.status === 'disabled'
            ? '账号已停用，无法签到'
            : account.status === 'expired'
              ? SESSION_EXPIRED_MESSAGE
              : '账号待连接，暂不能签到'
      }
    }
    if (!account.checkinEnabled) {
      return null
    }
    if (account.checkedInToday) {
      return {
        id: makeId('checkin-repeat'),
        accountId: account.id,
        platformType: account.platformType,
        time: isoNow(),
        success: false,
        message: '今日已完成签到'
      }
    }
    try {
      const result = await withAccountAuth(account, async (session) =>
        doCheckin(account.baseUrl, session.accessToken, session.userId)
      )
      const reward = quotaToMoney(result.quotaAwarded, account.quotaPerUnit)
      const log: CheckinLog = {
        id: makeId('checkin'),
        accountId: account.id,
        platformType: account.platformType,
        time: isoNow(),
        success: true,
        message: reward ? `签到成功，获得 $${reward.toFixed(2)} 额度` : result.message,
        reward
      }
      checkinLogs.value.unshift(log)
      checkinLogs.value = checkinLogs.value.slice(0, 100)
      await syncAccount(account.id)
      return log
    } catch (error) {
      return {
        id: makeId('checkin-error'),
        accountId: account.id,
        platformType: account.platformType,
        time: isoNow(),
        success: false,
        message: error instanceof Error ? error.message : '签到失败'
      }
    }
  }

  const checkinAll = async (): Promise<CheckinLog[]> => {
    const targets = accounts.value.filter((account) => isCheckinEligible(account))
    const results = await Promise.all(targets.map((account) => checkinAccount(account.id)))
    return results.filter((result): result is CheckinLog => result !== null)
  }

  const autoCheckinAccounts = async (): Promise<CheckinLog[]> => {
    const due = accounts.value.filter(
      (account) => isCheckinEligible(account) && !account.checkedInToday
    )
    if (!due.length) {
      return []
    }
    const results = await Promise.all(due.map((account) => checkinAccount(account.id)))
    return results.filter((result): result is CheckinLog => result !== null)
  }

  const summarizeCheckin = (
    results: CheckinLog[]
  ): { message: string; type: FeedbackType } => {
    if (!results.length) {
      return { message: '当前没有支持签到的账号', type: 'text' }
    }
    const successes = results.filter((result) => result.success)
    if (successes.length) {
      return { message: `完成 ${successes.length} 个账号签到`, type: 'success' }
    }
    const alreadyDone = results.every((result) => result.message.includes('今日已完成签到'))
    if (alreadyDone) {
      return { message: '支持签到的账号今日都已签到', type: 'text' }
    }
    const firstError = results.find((result) => !result.success)?.message
    return { message: firstError || '签到未完成', type: 'warning' }
  }

  const toAccountDraft = (account?: Account): AccountDraft => {
    if (!account) {
      return createEmptyAccountDraft()
    }
    return {
      id: account.id,
      alias: account.alias,
      siteName: account.siteName,
      baseUrl: account.baseUrl,
      platformType: account.platformType,
      authMode: account.authMode,
      username: account.username,
      password: '',
      accessToken: '',
      userId: account.userId,
      tags: [...account.tags]
    }
  }

  const saveAccount = async (draft: AccountDraft): Promise<Account> => {
    const now = isoNow()
    const existing = draft.id ? accountById(draft.id) : undefined
    const baseUrl = normalizeBaseUrl(draft.baseUrl)
    const hasFreshCredentials =
      draft.platformType === 'sub2api'
        ? Boolean(draft.username.trim() && draft.password) || Boolean(draft.accessToken.trim())
        : draft.authMode === 'access_token'
          ? Boolean(draft.accessToken.trim())
          : Boolean(draft.username.trim() && draft.password)
    if (!existing && !hasFreshCredentials) {
      throw new ApiError(
        draft.platformType === 'sub2api'
          ? '请填写邮箱和密码'
          : draft.authMode === 'access_token'
            ? '请填写系统访问令牌'
            : '请填写用户名和密码'
      )
    }

    let connected = existing
      ? {
          baseUrl,
          accessToken: sessionByAccount(existing.id)?.accessToken || '',
          refreshToken: sessionByAccount(existing.id)?.refreshToken || '',
          user: {
            id: Number(existing.userId) || 0,
            username: existing.username,
            display_name: existing.displayName,
            email: existing.email,
            group: existing.group,
            quota: 0,
            used_quota: 0,
            request_count: existing.requestCount,
            status: 1
          } as NewApiUser,
          quotaPerUnit: existing.quotaPerUnit,
          checkinEnabled: existing.checkinEnabled,
          systemName: existing.siteName
        }
      : null

    if (existing && normalizeBaseUrl(draft.baseUrl) !== existing.baseUrl && !hasFreshCredentials) {
      throw new ApiError('站点地址已变更，请重新登录或填写访问令牌')
    }

    if (hasFreshCredentials || !connected?.accessToken) {
      if (draft.platformType === 'sub2api') {
        const sub2 = await connectSub2Account({
          baseUrl,
          email: draft.username,
          password: draft.password,
          turnstileToken: draft.turnstileToken,
          accessToken: draft.accessToken,
          refreshToken: draft.refreshToken
        })
        connected = {
          baseUrl: sub2.baseUrl,
          accessToken: sub2.accessToken,
          refreshToken: sub2.refreshToken,
          user: {
            id: sub2.user.id,
            username: sub2.user.username,
            display_name: sub2.user.username,
            email: sub2.user.email,
            group: 'default',
            quota: sub2.user.balance ?? 0,
            used_quota: 0,
            request_count: 0,
            status: sub2.user.status === 'disabled' ? 0 : 1
          } as NewApiUser,
          quotaPerUnit: SUB2_QUOTA_PER_UNIT,
          checkinEnabled: false,
          systemName: sub2.settings.site_name || ''
        }
      } else {
        const newapi = await connectAccount({
          baseUrl,
          username: draft.username,
          password: draft.password,
          accessToken: draft.authMode === 'access_token' ? draft.accessToken : undefined,
          userId: draft.userId || existing?.userId
        })
        connected = {
          ...newapi,
          refreshToken: '',
          systemName: ''
        }
      }
    }

    const siteName = draft.siteName.trim() || connected.systemName?.trim() || hostnameOf(connected.baseUrl)
    const alias =
      draft.alias.trim() || connected.user.display_name || connected.user.username || siteName

    if (existing) {
      existing.alias = alias
      existing.siteName = siteName
      existing.baseUrl = connected.baseUrl
      existing.platformType = draft.platformType
      existing.authMode = draft.authMode
      existing.tags = [...draft.tags]
      existing.quotaPerUnit = connected.quotaPerUnit
      existing.checkinEnabled = connected.checkinEnabled
      existing.updatedAt = now
      const session = sessionByAccount(existing.id)
      if (session) {
        session.accessToken = connected.accessToken
        session.userId = String(connected.user.id || session.userId)
        if (connected.refreshToken) {
          session.refreshToken = connected.refreshToken
        }
      } else {
        sessions.value.push({
          accountId: existing.id,
          accessToken: connected.accessToken,
          userId: String(connected.user.id),
          refreshToken: connected.refreshToken || undefined
        })
      }
      if (hasFreshCredentials) {
        applyUserSnapshot(existing, connected.user)
      }
      await syncAccount(existing.id)
      persist()
      return existing
    }

    const account: Account = {
      id: makeId('account'),
      alias,
      siteName,
      baseUrl: connected.baseUrl,
      platformType: draft.platformType,
      authMode: draft.authMode,
      userId: String(connected.user.id),
      username: connected.user.username || draft.username.trim(),
      displayName: connected.user.display_name || '',
      email: connected.user.email || '',
      group: connected.user.group || 'default',
      quota: quotaToMoney(connected.user.quota ?? 0, connected.quotaPerUnit),
      usedQuota: quotaToMoney(connected.user.used_quota ?? 0, connected.quotaPerUnit),
      requestCount: connected.user.request_count ?? 0,
      quotaPerUnit: connected.quotaPerUnit,
      status: 'active',
      lastCheckin: null,
      checkedInToday: false,
      checkinEnabled: connected.checkinEnabled,
      tags: [...draft.tags],
      trend: [],
      lastSyncedAt: now,
      lastError: null,
      createdAt: now,
      updatedAt: now
    }
    applyUserSnapshot(account, connected.user)
    accounts.value.unshift(account)
    sessions.value.push({
      accountId: account.id,
      accessToken: connected.accessToken,
      userId: String(connected.user.id),
      refreshToken: connected.refreshToken || undefined
    })
    await syncAccount(account.id)
    persist()
    return account
  }

  const reloginAccount = async (accountId: string): Promise<'synced' | 'need-form'> => {
    const account = accountById(accountId)
    if (!account) {
      throw new ApiError('账号不存在')
    }
    if (account.platformType === 'sub2api' && canCaptureSiteSession()) {
      const captured = await captureSiteSession({
        baseUrl: account.baseUrl,
        email: account.email || account.username
      })
      const session = sessionByAccount(account.id)
      if (session) {
        session.accessToken = captured.accessToken
        session.refreshToken = captured.refreshToken || session.refreshToken
      } else {
        sessions.value.push({
          accountId: account.id,
          accessToken: captured.accessToken,
          userId: account.userId,
          refreshToken: captured.refreshToken || undefined
        })
      }
      persist()
      await syncAccount(account.id)
      return 'synced'
    }
    return 'need-form'
  }

  const deleteAccount = (accountId: string): void => {
    accounts.value = accounts.value.filter((account) => account.id !== accountId)
    sessions.value = sessions.value.filter((session) => session.accountId !== accountId)
    apiKeys.value = apiKeys.value.filter((apiKey) => apiKey.accountId !== accountId)
    checkinLogs.value = checkinLogs.value.filter((log) => log.accountId !== accountId)
    usageLogs.value = usageLogs.value.filter((log) => log.accountId !== accountId)
    Object.keys(revealedKeys.value).forEach((key) => {
      if (key.startsWith(`${accountId}:`)) {
        delete revealedKeys.value[key]
      }
    })
    if (selectedAccountId.value === accountId) {
      selectedAccountId.value = null
    }
    persist()
  }

  const toApiKeyDraft = (apiKey?: ApiKey, accountId = ''): ApiKeyDraft => {
    if (!apiKey) {
      const account = accountById(accountId)
      return {
        ...createEmptyApiKeyDraft(accountId),
        group: account?.group || 'default'
      }
    }
    return {
      id: apiKey.id,
      accountId: apiKey.accountId,
      name: apiKey.name,
      unlimitedQuota: apiKey.unlimitedQuota,
      remainQuota: apiKey.unlimitedQuota ? '' : String(apiKey.remainQuota),
      expiresAt: apiKey.expiresAt ? apiKey.expiresAt.slice(0, 10) : '',
      group: apiKey.group,
      modelLimitsText: apiKey.modelLimits.join(', '),
      allowIpsText: apiKey.allowIps.join(', '),
      crossGroupRetry: apiKey.crossGroupRetry
    }
  }

  const tokenPayload = (account: Account, draft: ApiKeyDraft, remoteId?: number): Record<string, unknown> => {
    const models = splitList(draft.modelLimitsText)
    const remainQuota = draft.unlimitedQuota
      ? 0
      : Math.round(Number(draft.remainQuota) * account.quotaPerUnit)
    return {
      id: remoteId,
      name: draft.name.trim(),
      unlimited_quota: draft.unlimitedQuota,
      remain_quota: Number.isFinite(remainQuota) ? Math.max(0, remainQuota) : 0,
      expired_time: dateInputToUnix(draft.expiresAt),
      group: draft.group || defaultGroupForAccount(account),
      model_limits_enabled: models.length > 0,
      model_limits: models.join(','),
      allow_ips: splitList(draft.allowIpsText).join('\n'),
      cross_group_retry: (draft.group || defaultGroupForAccount(account)) === 'auto' && draft.crossGroupRetry
    }
  }

  const saveApiKey = async (draft: ApiKeyDraft): Promise<ApiKey | null> => {
    const account = accountById(draft.accountId)
    if (!account) {
      return null
    }
    const existing = draft.id ? apiKeyById(draft.id) : undefined
    await withAccountAuth(account, async (session) => {
      if (account.platformType === 'sub2api') {
        const groups = await loadTokenGroups(account.id)
        const selectedGroup = groups.find((group) => group.name === draft.group)
        const remainQuota = draft.unlimitedQuota ? 0 : Number(draft.remainQuota)
        const expiresAt = draft.expiresAt.trim()
        const expiresInDays = expiresAt
          ? Math.max(1, Math.ceil((new Date(`${expiresAt}T23:59:59`).getTime() - Date.now()) / 86400000))
          : undefined
        const payload: Record<string, unknown> = {
          name: draft.name.trim(),
          group_id: selectedGroup?.remoteId ?? null,
          quota: Number.isFinite(remainQuota) ? Math.max(0, remainQuota) : 0,
          ip_whitelist: splitList(draft.allowIpsText)
        }
        if (expiresInDays) {
          payload.expires_in_days = expiresInDays
        }
        if (existing) {
          await updateSub2Key(account.baseUrl, session.accessToken, existing.remoteId, payload)
        } else {
          await createSub2Key(account.baseUrl, session.accessToken, payload)
        }
        return
      }
      if (existing) {
        await updateToken(
          account.baseUrl,
          session.accessToken,
          session.userId,
          tokenPayload(account, draft, existing.remoteId)
        )
        return
      }
      await createToken(
        account.baseUrl,
        session.accessToken,
        session.userId,
        tokenPayload(account, draft)
      )
    })
    await syncAccount(account.id)
    if (existing) {
      return apiKeyById(existing.id) ?? null
    }
    const created = apiKeysForAccount(account.id)[0]
    if (created && account.platformType !== 'sub2api') {
      try {
        created.key = await withAccountAuth(account, async (session) =>
          revealTokenKey(account.baseUrl, session.accessToken, session.userId, created.remoteId)
        )
        created.keyMasked = false
        revealedKeys.value[created.id] = created.key
        persist()
      } catch {
        created.keyMasked = true
      }
    }
    return created ?? null
  }

  const deleteApiKey = async (id: string): Promise<void> => {
    const apiKey = apiKeyById(id)
    if (!apiKey) {
      return
    }
    const account = accountById(apiKey.accountId)
    if (account) {
      await withAccountAuth(account, async (session) => {
        if (account.platformType === 'sub2api') {
          await deleteSub2Key(account.baseUrl, session.accessToken, apiKey.remoteId)
        } else {
          await deleteToken(account.baseUrl, session.accessToken, session.userId, apiKey.remoteId)
        }
      })
    }
    apiKeys.value = apiKeys.value.filter((item) => item.id !== id)
    delete revealedKeys.value[id]
    persist()
  }

  const toggleApiKeyStatus = async (id: string): Promise<ApiKey | undefined> => {
    const apiKey = apiKeyById(id)
    if (!apiKey || apiKey.status === 'expired' || apiKey.status === 'exhausted') {
      return apiKey
    }
    const account = accountById(apiKey.accountId)
    if (!account) {
      throw new ApiError(SESSION_EXPIRED_MESSAGE, 401)
    }
    const nextStatus = apiKey.status === 'disabled' ? 1 : 2
    await withAccountAuth(account, async (session) => {
      if (account.platformType === 'sub2api') {
        await updateSub2Key(account.baseUrl, session.accessToken, apiKey.remoteId, {
          status: apiKey.status === 'disabled' ? 'active' : 'inactive'
        })
        return
      }
      await updateToken(
        account.baseUrl,
        session.accessToken,
        session.userId,
        { id: apiKey.remoteId, status: nextStatus },
        true
      )
    })
    await syncAccount(account.id)
    return apiKeyById(id)
  }

  const revealApiKey = async (id: string): Promise<string> => {
    const apiKey = apiKeyById(id)
    if (!apiKey) {
      throw new ApiError('未找到该 API Key')
    }
    if (!apiKey.keyMasked && apiKey.key) {
      return apiKey.key
    }
    if (revealedKeys.value[id]) {
      apiKey.key = revealedKeys.value[id]
      apiKey.keyMasked = false
      return apiKey.key
    }
    const account = accountById(apiKey.accountId)
    if (!account) {
      throw new ApiError(SESSION_EXPIRED_MESSAGE, 401)
    }
    const key = await withAccountAuth(account, async (session) =>
      account.platformType === 'sub2api'
        ? (await fetchSub2KeyById(account.baseUrl, session.accessToken, apiKey.remoteId)).key || ''
        : await revealTokenKey(account.baseUrl, session.accessToken, session.userId, apiKey.remoteId)
    )
    if (!key) {
      throw new ApiError('站点未返回完整 Key')
    }
    apiKey.key = key
    apiKey.keyMasked = false
    revealedKeys.value[id] = key
    persist()
    return key
  }

  const updateSettings = (patch: Partial<PrototypeSettings>): void => {
    Object.assign(settings, patch)
    accounts.value.forEach((account) => {
      if (account.status !== 'pending') {
        updateAccountStatus(account)
      }
    })
    persist()
  }

  const notify = (message: string, type: FeedbackType = 'success', duration = 2200): void => {
    if (feedbackTimer) {
      clearTimeout(feedbackTimer)
    }
    feedback.message = message
    feedback.type = type
    feedback.visible = true
    if (duration > 0) {
      feedbackTimer = setTimeout(() => {
        feedback.visible = false
      }, duration)
    }
  }

  const dismissFeedback = (): void => {
    if (feedbackTimer) {
      clearTimeout(feedbackTimer)
      feedbackTimer = undefined
    }
    feedback.visible = false
  }

  return {
    accounts,
    apiKeys,
    checkinLogs,
    usageLogs,
    settings,
    feedback,
    searchTerm,
    selectedAccountStatus,
    selectedAccountId,
    selectedKeyId,
    isRefreshing,
    hydrated,
    filteredAccounts,
    totalQuota,
    totalUsedQuota,
    totalRequestCount,
    todayUsage,
    todayCheckinStatus,
    lowQuotaAccounts,
    expiredAccounts,
    activeApiKeyCount,
    accountById,
    apiKeyById,
    apiKeysForAccount,
    displayAccountName,
    accountTypeLabel,
    keyCountForAccount,
    isCheckedInToday,
    groupsForAccount,
    tokenGroupLabel,
    defaultGroupForAccount,
    modelsForGroup,
    loadTokenGroups,
    loadGroupModels,
    hydrate,
    refreshAllAccounts,
    syncAccount,
    checkinAccount,
    checkinAll,
    autoCheckinAccounts,
    summarizeCheckin,
    toAccountDraft,
    saveAccount,
    reloginAccount,
    deleteAccount,
    toApiKeyDraft,
    saveApiKey,
    deleteApiKey,
    toggleApiKeyStatus,
    revealApiKey,
    updateSettings,
    notify,
    dismissFeedback
  }
})
