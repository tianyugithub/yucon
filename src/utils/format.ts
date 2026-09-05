export const formatCompactCount = (count: number): string => {
  const value = Math.max(0, Math.floor(Number(count) || 0))
  return value > 99 ? '99+' : String(value)
}

export const formatCurrency = (value: number): string =>
  `$${value.toLocaleString('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2
  })}`

export const formatDateTime = (iso: string | null): string => {
  if (!iso) {
    return '—'
  }
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) {
    return '时间未知'
  }
  const pad = (value: number): string => value.toString().padStart(2, '0')
  return `${pad(date.getMonth() + 1)}/${pad(date.getDate())} ${pad(date.getHours())}:${pad(
    date.getMinutes()
  )}`
}

export const formatShortDate = (iso: string): string => {
  const date = new Date(iso)
  if (Number.isNaN(date.getTime())) {
    return '未知日期'
  }
  return `${date.getMonth() + 1}月${date.getDate()}日`
}

export const maskSecret = (value?: string): string => {
  if (!value) {
    return '未配置'
  }
  if (value.length <= 8) {
    return '••••••••'
  }
  return `${value.slice(0, 4)}••••••${value.slice(-4)}`
}

export const displayDomain = (value: string): string =>
  value.replace(/^https?:\/\//, '').replace(/\/$/, '')
