export const DEFAULT_QUOTA_PER_UNIT = 500000

export const roundMoney = (value: number): number => Math.round(value * 100) / 100

export const quotaToMoney = (
  quota: number,
  quotaPerUnit = DEFAULT_QUOTA_PER_UNIT
): number => {
  const unit = quotaPerUnit > 0 ? quotaPerUnit : DEFAULT_QUOTA_PER_UNIT
  return roundMoney(quota / unit)
}

export const moneyToQuota = (
  money: number,
  quotaPerUnit = DEFAULT_QUOTA_PER_UNIT
): number => {
  const unit = quotaPerUnit > 0 ? quotaPerUnit : DEFAULT_QUOTA_PER_UNIT
  return Math.round(money * unit)
}

export const unixToIso = (value?: number | null): string | null => {
  if (!value || value <= 0) {
    return null
  }
  const millis = value > 1_000_000_000_000 ? value : value * 1000
  const date = new Date(millis)
  return Number.isNaN(date.getTime()) ? null : date.toISOString()
}

export const isoToUnix = (value: string | null): number => {
  if (!value) {
    return -1
  }
  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return -1
  }
  return Math.floor(date.getTime() / 1000)
}

export const dateInputToUnix = (value: string): number => {
  const trimmed = value.trim()
  if (!trimmed) {
    return -1
  }
  if (trimmed.includes('T') || trimmed.includes(' ')) {
    return isoToUnix(trimmed.replace(' ', 'T'))
  }
  const date = new Date(`${trimmed}T23:59:59`)
  return Number.isNaN(date.getTime()) ? -1 : Math.floor(date.getTime() / 1000)
}

export const formatGroupRatio = (value: unknown): string => {
  if (value === '自动' || value === 'auto') {
    return '自动'
  }
  const ratio = Number(value)
  if (!Number.isFinite(ratio)) {
    return '—'
  }
  const text = Number.isInteger(ratio) ? String(ratio) : String(Number(ratio.toFixed(4)))
  return `×${text}`
}

export const weekdayLabel = (iso: string): string => {
  const labels = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
  return labels[new Date(iso).getDay()] ?? '今天'
}
