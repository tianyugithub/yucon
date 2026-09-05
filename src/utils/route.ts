type RouteQuery = Record<string, unknown> | undefined

export const getRouteParam = (query: RouteQuery, key: string): string | undefined => {
  const value = query?.[key]
  if (typeof value === 'string' && value) {
    return value
  }

  if (typeof window === 'undefined') {
    return undefined
  }

  const [, queryString = ''] = window.location.hash.split('?')
  const hashValue = new URLSearchParams(queryString).get(key)
  return hashValue || undefined
}
