<script setup lang="ts">
import { nextTick, onBeforeUnmount, onMounted, ref, watch } from 'vue'
import { loadTurnstileScript } from '@/utils/turnstile'

const props = withDefaults(
  defineProps<{
    siteKey: string
    theme?: 'light' | 'dark' | 'auto'
    resetSignal?: number
  }>(),
  {
    theme: 'light',
    resetSignal: 0
  }
)

const emit = defineEmits<{
  token: [value: string]
  expire: []
  error: [message: string]
}>()

const hostId = `yc-turnstile-${Math.random().toString(36).slice(2, 10)}`
const ready = ref(false)
const loadError = ref('')
let widgetId: string | null = null
let renderTimer: ReturnType<typeof setTimeout> | undefined

const hostElement = (): HTMLElement | null => {
  if (typeof document === 'undefined') {
    return null
  }
  return document.getElementById(hostId)
}

const destroyWidget = (): void => {
  if (widgetId && window.turnstile) {
    try {
      window.turnstile.remove(widgetId)
    } catch {
      // Widget may already be gone after a remount.
    }
  }
  widgetId = null
}

const renderWidget = async (): Promise<void> => {
  loadError.value = ''
  if (!props.siteKey.trim()) {
    return
  }
  try {
    await loadTurnstileScript()
    await nextTick()
    const el = hostElement()
    if (!el || !window.turnstile) {
      throw new Error('无法初始化 Cloudflare 验证')
    }
    destroyWidget()
    el.innerHTML = ''
    widgetId = window.turnstile.render(el, {
      sitekey: props.siteKey,
      theme: props.theme,
      size: 'flexible',
      retry: 'auto',
      callback: (token: string) => {
        emit('token', token)
      },
      'expired-callback': () => {
        emit('expire')
      },
      'error-callback': () => {
        emit('error', '人机验证失败，请点击验证框重试')
      }
    })
    ready.value = true
    if (renderTimer) {
      clearTimeout(renderTimer)
    }
    renderTimer = setTimeout(() => {
      if (!el.querySelector('iframe')) {
        emit('error', '当前域名无法完成该站点的 Cloudflare 验证')
      }
    }, 4000)
  } catch (error) {
    ready.value = false
    loadError.value = error instanceof Error ? error.message : '无法加载 Cloudflare 验证'
    emit('error', loadError.value)
  }
}

const resetWidget = (): void => {
  if (widgetId && window.turnstile) {
    window.turnstile.reset(widgetId)
    return
  }
  void renderWidget()
}

onMounted(() => {
  void renderWidget()
})

onBeforeUnmount(() => {
  if (renderTimer) {
    clearTimeout(renderTimer)
  }
  destroyWidget()
})

watch(
  () => [props.siteKey, props.theme],
  () => {
    void renderWidget()
  }
)

watch(
  () => props.resetSignal,
  (current, previous) => {
    if (current !== previous) {
      resetWidget()
    }
  }
)

defineExpose({ reset: resetWidget })
</script>

<template>
  <view class="turnstile-widget">
    <!-- #ifdef H5 -->
    <div :id="hostId" class="turnstile-widget__host"></div>
    <!-- #endif -->
    <!-- #ifndef H5 -->
    <view :id="hostId" class="turnstile-widget__host" />
    <!-- #endif -->
    <text v-if="loadError" class="turnstile-widget__error">{{ loadError }}</text>
    <text v-else-if="!ready" class="turnstile-widget__hint">正在加载人机验证…</text>
  </view>
</template>

<style scoped lang="scss">
.turnstile-widget {
  min-height: 72px;

  &__host {
    min-height: 65px;
  }

  &__hint,
  &__error {
    display: block;
    margin-top: 8rpx;
    font-size: 20rpx;
    line-height: 1.4;
  }

  &__hint {
    color: var(--yc-muted);
  }

  &__error {
    color: #c54638;
  }
}
</style>
