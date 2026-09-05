<script setup lang="ts">
import { computed } from 'vue'
import { NutTag } from '@/components/nutui'
import type { ApiKeyStatus } from '@/types/domain'

const props = withDefaults(
  defineProps<{
    status: ApiKeyStatus
    compact?: boolean
  }>(),
  {
    compact: false
  }
)

const meta = computed(() => {
  const states: Record<ApiKeyStatus, { label: string; color: string; background: string }> = {
    enabled: { label: '启用', color: '#168553', background: '#e7f7ef' },
    disabled: { label: '已停用', color: '#69707c', background: '#eef0f3' },
    expired: { label: '已过期', color: '#b05f00', background: '#fff2dc' },
    exhausted: { label: '已耗尽', color: '#c23036', background: '#ffe9eb' }
  }
  return states[props.status]
})
</script>

<template>
  <NutTag
    round
    :custom-color="meta.background"
    :text-color="meta.color"
    class="key-status-badge"
    :class="{ 'key-status-badge--compact': compact }"
  >
    <view class="key-status-badge__content">
      <view class="key-status-badge__dot" :style="{ background: meta.color }" />
      <text>{{ meta.label }}</text>
    </view>
  </NutTag>
</template>

<style scoped lang="scss">
.key-status-badge {
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
