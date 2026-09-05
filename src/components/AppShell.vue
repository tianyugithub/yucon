<script setup lang="ts">
import { computed, nextTick, onMounted, onUnmounted, ref, watch } from 'vue'
import BrandHeader from '@/components/BrandHeader.vue'
import TabIcon from '@/components/TabIcon.vue'
import { NutTabbar, NutTabbarItem } from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'

type TabIndex = 0 | 1 | 2 | 3

const props = withDefaults(
  defineProps<{
    currentTab?: TabIndex
    title?: string
    subtitle?: string
    showBack?: boolean
    backUrl?: string
    showHeader?: boolean
  }>(),
  {
    currentTab: undefined,
    title: '',
    subtitle: '',
    showBack: false,
    backUrl: '/pages/dashboard/index',
    showHeader: true
  }
)

const store = usePrototypeStore()
const activeTab = ref<string>(String(props.currentTab ?? 0))
const shouldShowTabbar = computed(() => props.currentTab !== undefined)

const tabRoutes = [
  '/pages/dashboard/index',
  '/pages/accounts/index',
  '/pages/logs/index',
  '/pages/profile/index'
] as const

const handleTabSwitch = (_item: unknown, target: string | number): void => {
  const nextTab = Number(target)
  if (!Number.isInteger(nextTab) || nextTab < 0 || nextTab >= tabRoutes.length) {
    return
  }
  if (nextTab === props.currentTab) {
    return
  }
  uni.reLaunch({ url: tabRoutes[nextTab] })
}

const topRef = ref<unknown>(null)
const spacerPx = ref(0)
let headerObserver: ResizeObserver | undefined

const unwrapEl = (value: unknown): HTMLElement | null => {
  if (value instanceof HTMLElement) {
    return value
  }
  if (value && typeof value === 'object' && '$el' in value) {
    const el = (value as { $el: unknown }).$el
    if (el instanceof HTMLElement) {
      return el
    }
  }
  return null
}

const syncHeaderSpacer = (): void => {
  const node = unwrapEl(topRef.value)
  if (!node) {
    return
  }
  spacerPx.value = node.offsetHeight
}

const observeHeader = (): void => {
  headerObserver?.disconnect()
  const node = unwrapEl(topRef.value)
  if (!node) {
    return
  }
  syncHeaderSpacer()
  if (typeof ResizeObserver === 'undefined') {
    return
  }
  headerObserver = new ResizeObserver(syncHeaderSpacer)
  headerObserver.observe(node)
}

onMounted(() => {
  void nextTick(observeHeader)
})

watch(
  () => props.showHeader,
  () => {
    void nextTick(observeHeader)
  }
)

onUnmounted(() => {
  headerObserver?.disconnect()
})
</script>

<template>
  <view
    class="app-shell yc-page"
    :class="{
      'yc-page--dark': store.settings.darkMode,
      'n-dark': store.settings.darkMode
    }"
  >
    <view
      v-if="showHeader"
      class="app-shell__top-spacer"
      :style="{ height: spacerPx ? `${spacerPx}px` : '116rpx' }"
    />
    <view v-if="showHeader" ref="topRef" class="app-shell__top">
      <BrandHeader
        :title="title"
        :subtitle="subtitle"
        :show-back="showBack"
        :back-url="backUrl"
        :dark="store.settings.darkMode"
      >
        <template #actions>
          <slot name="header-actions" />
        </template>
      </BrandHeader>
      <view v-if="$slots['header-extra']" class="app-shell__header-extra">
        <slot name="header-extra" />
      </view>
    </view>

    <slot />

    <NutTabbar
      v-if="shouldShowTabbar"
      v-model="activeTab"
      class="app-shell__tabbar"
      bottom
      placeholder
      safe-area-inset-bottom
      active-color="#fa2c19"
      unactive-color="#848b96"
      @tab-switch="handleTabSwitch"
    >
      <NutTabbarItem name="0" tab-title="看板">
        <template #icon>
          <TabIcon class="app-shell__tab-icon" name="dashboard" />
        </template>
      </NutTabbarItem>
      <NutTabbarItem name="1" tab-title="账号">
        <template #icon>
          <TabIcon class="app-shell__tab-icon" name="accounts" />
        </template>
      </NutTabbarItem>
      <NutTabbarItem name="2" tab-title="日志">
        <template #icon>
          <TabIcon class="app-shell__tab-icon" name="logs" />
        </template>
      </NutTabbarItem>
      <NutTabbarItem name="3" tab-title="我的">
        <template #icon>
          <TabIcon class="app-shell__tab-icon" name="profile" />
        </template>
      </NutTabbarItem>
    </NutTabbar>

    <view
      v-if="store.feedback.visible"
      class="app-shell__feedback"
      :class="`app-shell__feedback--${store.feedback.type}`"
      @click="store.dismissFeedback"
    >
      {{ store.feedback.message }}
    </view>
  </view>
</template>

<style scoped lang="scss">
.app-shell {
  min-height: 100%;
  overscroll-behavior: none;
  transition: background-color 0.2s ease;

  &__top-spacer {
    flex: none;
  }

  &__top {
    position: fixed;
    top: 0;
    right: 0;
    left: 0;
    z-index: 100;
    background: var(--yc-page);
    transform: translateZ(0);
    backface-visibility: hidden;
  }

  &__header-extra {
    padding: 0 30rpx 20rpx;
  }

  &__tabbar {
    min-height: calc(52px + env(safe-area-inset-bottom));

    :deep(.nut-tabbar) {
      box-sizing: border-box;
      height: 52px;
      min-height: 52px;
      padding: 6px 0 5px;
      overflow: hidden;
      border-top: 1rpx solid rgba(17, 24, 39, 0.06);
      border-radius: 16px 16px 0 0;
      background: rgba(255, 255, 255, 0.98);
      box-shadow: 0 -10rpx 28rpx rgba(25, 29, 37, 0.08);
    }

    :deep(.nut-tabbar-bottom) {
      transform: translateZ(0);
      backface-visibility: hidden;
    }

    :deep(.nut-tabbar-safebottom) {
      height: auto;
      min-height: calc(52px + env(safe-area-inset-bottom));
      padding-bottom: calc(5px + env(safe-area-inset-bottom));
    }

    :deep(.nut-tabbar-item) {
      height: auto;
      min-height: 0;
      align-self: stretch;
    }

    :deep(.nut-tabbar-item_icon-box) {
      justify-content: center;
      gap: 2px;
    }

    :deep(.nut-tabbar-item_icon-box_nav-word) {
      margin-top: 0;
      font-size: 10px;
      font-weight: 650;
      line-height: 1.2;
    }
  }

  &__tab-icon {
    display: block;
    width: 18px;
    height: 18px;
  }

  &__feedback {
    position: fixed;
    z-index: 999;
    right: 48rpx;
    bottom: calc(64px + env(safe-area-inset-bottom));
    left: 48rpx;
    padding: 22rpx 28rpx;
    border-radius: 20rpx;
    background: rgba(25, 27, 30, 0.94);
    box-shadow: 0 16rpx 36rpx rgba(0, 0, 0, 0.18);
    color: #fff;
    text-align: center;
    font-size: 23rpx;
    font-weight: 650;

    &--error {
      background: rgba(190, 38, 48, 0.96);
    }

    &--warning {
      background: rgba(188, 108, 5, 0.96);
    }
  }

  &.yc-page--dark {
    .app-shell__tabbar {
      :deep(.nut-tabbar) {
        border-color: rgba(255, 255, 255, 0.08);
        background: #1b1d20;
        box-shadow: 0 -10rpx 28rpx rgba(0, 0, 0, 0.28);
      }
    }
  }
}

/* #ifdef H5 */
@media screen and (min-width: 768px) {
  .app-shell {
    &__top {
      left: 50%;
      width: 750rpx;
      right: auto;
      transform: translate3d(-50%, 0, 0);
    }

    &__tabbar {
      :deep(.nut-tabbar-bottom) {
        width: 750rpx;
        left: 50%;
        transform: translate3d(-50%, 0, 0);
      }
    }
  }
}
/* #endif */
</style>
