<script setup lang="ts">
import BrandMark from '@/components/BrandMark.vue'

const props = withDefaults(
  defineProps<{
    title?: string
    subtitle?: string
    showBack?: boolean
    backUrl?: string
    dark?: boolean
  }>(),
  {
    title: '',
    subtitle: '',
    showBack: false,
    backUrl: '/pages/dashboard/index',
    dark: false
  }
)

const handleBack = (): void => {
  uni.reLaunch({ url: props.backUrl })
}
</script>

<template>
  <view class="brand-header" :class="{ 'brand-header--dark': dark }">
    <button
      v-if="showBack"
      class="brand-header__back"
      aria-label="返回"
      @click="handleBack"
    >
      <svg
        class="brand-header__back-icon"
        viewBox="0 0 24 24"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        aria-hidden="true"
      >
        <path d="M15 18L9 12L15 6" />
      </svg>
    </button>
    <view class="brand-header__identity">
      <BrandMark
        v-if="!title"
        :size="82"
        :show-wordmark="true"
        :inverse="dark"
      />
      <view v-else class="brand-header__title-block">
        <text class="brand-header__title">{{ title }}</text>
        <text v-if="subtitle" class="brand-header__subtitle">{{ subtitle }}</text>
      </view>
    </view>
    <view class="brand-header__actions">
      <slot name="actions" />
    </view>
  </view>
</template>

<style scoped lang="scss">
.brand-header {
  display: flex;
  align-items: center;
  min-height: 116rpx;
  padding: calc(env(safe-area-inset-top) + 16rpx) 30rpx 16rpx;
  color: $yc-ink;

  &__back {
    display: flex;
    width: 56rpx;
    height: 56rpx;
    align-items: center;
    justify-content: center;
    margin-right: 24rpx;
    padding: 0;
    border: 0;
    border-radius: 18rpx;
    background: rgba(26, 26, 26, 0.06);
    color: inherit;
  }

  &__back-icon {
    display: block;
    width: 28rpx;
    height: 28rpx;
    stroke: currentColor;
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 2.4;
  }

  &__identity {
    min-width: 0;
    flex: 1;
  }

  &__title-block {
    display: flex;
    min-width: 0;
    flex-direction: column;
  }

  &__title {
    overflow: hidden;
    color: inherit;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 38rpx;
    font-weight: 800;
    letter-spacing: -1rpx;
    line-height: 1.15;
  }

  &__subtitle {
    margin-top: 8rpx;
    color: $yc-muted;
    font-size: 23rpx;
  }

  &__actions {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    margin-left: 16rpx;
  }

  &--dark {
    color: #fff;

    .brand-header__back {
      background: rgba(255, 255, 255, 0.12);
    }

    .brand-header__subtitle {
      color: rgba(255, 255, 255, 0.6);
    }
  }
}
</style>
