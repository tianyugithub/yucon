/// <reference types="vite/client" />
/// <reference types="@dcloudio/types" />
/// <reference types="@uni-helper/uni-app-types" />

declare module '*.vue' {
  import type { DefineComponent } from 'vue'
  const component: DefineComponent<Record<string, never>, Record<string, never>, unknown>
  export default component
}

interface TurnstileRenderOptions {
  sitekey: string
  callback?: (token: string) => void
  'expired-callback'?: () => void
  'error-callback'?: () => void
  theme?: 'light' | 'dark' | 'auto'
  size?: 'normal' | 'compact' | 'flexible'
  retry?: 'auto' | 'never'
}

interface TurnstileInstance {
  render: (element: string | HTMLElement, options: TurnstileRenderOptions) => string
  reset: (widgetId: string) => void
  remove: (widgetId: string) => void
}

interface Window {
  turnstile?: TurnstileInstance
}
