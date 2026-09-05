<script setup lang="ts">
import { computed, ref } from 'vue'
import KeyStatusBadge from '@/components/KeyStatusBadge.vue'
import ModelBrandIcon from '@/components/ModelBrandIcon.vue'
import TabIcon from '@/components/TabIcon.vue'
import { formatCurrency, formatShortDate, maskSecret } from '@/utils/format'
import { copyText } from '@/utils/clipboard'
import type { ApiKey } from '@/types/domain'
import { usePrototypeStore } from '@/stores/usePrototypeStore'

const props = defineProps<{
  apiKey: ApiKey
}>()

const emit = defineEmits<{
  open: []
}>()

const store = usePrototypeStore()
const copying = ref(false)

const quotaText = computed(() =>
  props.apiKey.unlimitedQuota
    ? '无限额度'
    : formatCurrency(props.apiKey.remainQuota)
)

const expiryText = computed(() =>
  props.apiKey.expiresAt ? formatShortDate(props.apiKey.expiresAt) : '永不过期'
)

const copyKey = async (): Promise<void> => {
  if (copying.value) {
    return
  }
  copying.value = true
  try {
    const value = await store.revealApiKey(props.apiKey.id)
    await copyText(value)
    store.notify('API Key 已复制')
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '复制失败', 'error')
  } finally {
    copying.value = false
  }
}
</script>

<template>
  <view class="api-key-card yc-card" role="button" @click="emit('open')">
    <view class="api-key-card__head">
      <view class="api-key-card__identity">
        <view class="api-key-card__icon">
          <TabIcon name="keys" />
        </view>
        <view class="api-key-card__name-block">
          <text class="api-key-card__name">{{ apiKey.name }}</text>
          <text class="api-key-card__group">{{ store.tokenGroupLabel(apiKey.accountId, apiKey.group) }}</text>
          <view v-if="apiKey.modelLimits.length" class="api-key-card__models">
            <ModelBrandIcon
              v-for="name in apiKey.modelLimits.slice(0, 4)"
              :key="name"
              :model="name"
              size="sm"
            />
            <text v-if="apiKey.modelLimits.length > 4">+{{ apiKey.modelLimits.length - 4 }}</text>
          </view>
        </view>
      </view>
      <KeyStatusBadge :status="apiKey.status" compact />
    </view>

    <view class="api-key-card__secret" @click.stop="copyKey">
      <text>API Key</text>
      <view class="api-key-card__secret-row">
        <text class="api-key-card__secret-value">{{ maskSecret(apiKey.key) }}</text>
        <text class="api-key-card__copy">{{ copying ? '复制中' : '复制' }}</text>
      </view>
    </view>

    <view class="api-key-card__meta">
      <view>
        <text class="api-key-card__meta-label">剩余额度</text>
        <text class="api-key-card__meta-value">{{ quotaText }}</text>
      </view>
      <view>
        <text class="api-key-card__meta-label">已使用</text>
        <text class="api-key-card__meta-value">{{ formatCurrency(apiKey.usedQuota) }}</text>
      </view>
      <view>
        <text class="api-key-card__meta-label">有效期</text>
        <text class="api-key-card__meta-value">{{ expiryText }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.api-key-card {
  padding: 26rpx;
  transition: transform 0.18s ease;

  &:active {
    transform: scale(0.99);
  }

  &__head,
  &__identity,
  &__meta {
    display: flex;
    align-items: center;
  }

  &__head {
    justify-content: space-between;
  }

  &__identity {
    min-width: 0;
  }

  &__icon {
    display: flex;
    width: 62rpx;
    height: 62rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 20rpx;
    background: #edf4ff;
    color: #3178df;

    :deep(.tab-icon) {
      width: 32rpx;
      height: 32rpx;
    }
  }

  &__name-block {
    display: flex;
    min-width: 0;
    flex-direction: column;
    margin-left: 16rpx;
  }

  &__name {
    overflow: hidden;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 29rpx;
    font-weight: 750;
  }

  &__group {
    margin-top: 5rpx;
    color: var(--yc-muted);
    font-size: 20rpx;
  }

  &__models {
    display: flex;
    align-items: center;
    margin-top: 10rpx;

    :deep(.model-brand-icon) {
      box-shadow: 0 0 0 3rpx var(--yc-surface);
    }

    :deep(.model-brand-icon + .model-brand-icon) {
      margin-left: -8rpx;
    }

    text {
      margin-left: 8rpx;
      color: var(--yc-muted);
      font-size: 18rpx;
      font-weight: 650;
    }
  }

  &__secret {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16rpx;
    margin-top: 22rpx;
    padding: 16rpx 18rpx;
    border-radius: 15rpx;
    background: #f7f8fa;
    color: var(--yc-muted);
    font-size: 21rpx;
  }

  &__secret-row {
    display: flex;
    min-width: 0;
    align-items: center;
    gap: 12rpx;
  }

  &__secret-value {
    overflow: hidden;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 20rpx;
  }

  &__copy {
    flex: none;
    color: $yc-primary;
    font-size: 22rpx;
    font-weight: 750;
  }

  &__meta {
    justify-content: space-between;
    gap: 16rpx;
    margin-top: 20rpx;
    color: var(--yc-muted);
  }

  &__meta-label,
  &__meta-value {
    display: block;
  }

  &__meta-label {
    font-size: 19rpx;
  }

  &__meta-value {
    margin-top: 5rpx;
    color: var(--yc-ink);
    font-size: 21rpx;
    font-weight: 700;
  }
}
</style>
