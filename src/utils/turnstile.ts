export const TURNSTILE_SCRIPT_SRC = 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'

let loader: Promise<void> | null = null

export const loadTurnstileScript = (): Promise<void> => {
  if (typeof document === 'undefined') {
    return Promise.reject(new Error('当前环境无法显示人机验证'))
  }
  if (window.turnstile) {
    return Promise.resolve()
  }
  if (loader) {
    return loader
  }
  loader = new Promise((resolve, reject) => {
    const existing = document.querySelector<HTMLScriptElement>('script[data-yc-turnstile]')
    if (existing) {
      if (window.turnstile) {
        resolve()
        return
      }
      existing.addEventListener('load', () => resolve(), { once: true })
      existing.addEventListener(
        'error',
        () => {
          loader = null
          reject(new Error('无法加载 Cloudflare 验证'))
        },
        { once: true }
      )
      return
    }
    const script = document.createElement('script')
    script.src = TURNSTILE_SCRIPT_SRC
    script.async = true
    script.defer = true
    script.dataset.ycTurnstile = 'true'
    script.onload = () => resolve()
    script.onerror = () => {
      loader = null
      reject(new Error('无法加载 Cloudflare 验证'))
    }
    document.head.appendChild(script)
  })
  return loader
}
