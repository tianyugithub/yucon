<script setup lang="ts">
import { computed } from 'vue'
import { NutTag } from '@/components/nutui'
import type { AccountStatus } from '@/types/domain'

const props = withDefaults(
  defineProps<{
    status: AccountStatus
    compact?: boolean
  }>(),
  {
    compact: false
  }
)

const meta = computed(() => {
  const states: Record<AccountStatus, { label: string; color: string; background: string }> = {
    active: { label: '正常', color: '#168553', background: '#e7f7ef' },
    low: { label: '低额度', color: '#b05f00', background: '#fff2dc' },
    disabled: { label: '已停用', color: '#69707c', background: '#eef0f3' },
    pending: { label: '待同步', color: '#3178df', background: '#edf4ff' },
    expired: { label: '需重新登录', color: '#be2630', background: '#fde8e6' }
  }
  return states[props.status]
})
</script>

<template>
  <NutTag
    round
    :custom-color="meta.background"
    :text-color="meta.color"
    class="account-status-badge"
    :class="{ 'account-status-badge--compact': compact }"
  >
    <view class="account-status-badge__content">
      <view class="account-status-badge__dot" :style="{ background: meta.color }" />
      <text>{{ meta.label }}</text>
    </view>
  </NutTag>
</template>

<style scoped lang="scss">
.account-status-badge {
  flex: none;

  :deep(.nut-tag) {
    padding: 7rpx 13rpx;
    border: 0;
  }

  &__content {
    display: flex;
    align-items: center;
    gap: 8rpx;
    font-size: 21rpx;
    font-weight: 700;
    line-height: 1;
  }

  &__dot {
    width: 10rpx;
    height: 10rpx;
    border-radius: 50%;
  }

  &--compact {
    :deep(.nut-tag) {
      padding: 5rpx 10rpx;
    }
  }
}
</style>
