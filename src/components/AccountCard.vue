<script setup lang="ts">
import { computed } from 'vue'
import AccountStatusBadge from '@/components/AccountStatusBadge.vue'
import { getPlatformPreset } from '@/constants/platform-presets'
import { formatCurrency, formatDateTime } from '@/utils/format'
import type { Account } from '@/types/domain'

const props = defineProps<{
  account: Account
  keyCount: number
  checkedIn?: boolean
}>()

const emit = defineEmits<{
  open: []
}>()

const preset = computed(() => getPlatformPreset(props.account.platformType))
const showsCheckin = computed(() => props.account.checkinEnabled)
const metaLabel = computed(() => (showsCheckin.value ? '最近签到' : '最近同步'))
const metaValue = computed(() => {
  if (!showsCheckin.value) {
    return props.account.lastSyncedAt ? formatDateTime(props.account.lastSyncedAt) : '尚未同步'
  }
  if (props.checkedIn) {
    return '今日已签到'
  }
  return props.account.lastCheckin ? formatDateTime(props.account.lastCheckin) : '尚未签到'
})
</script>

<template>
  <view
    class="account-card yc-card"
    :class="{
      'account-card--low': account.status === 'low',
      'account-card--expired': account.status === 'expired'
    }"
    role="button"
    @click="emit('open')"
  >
    <view class="account-card__head">
      <view class="account-card__identity">
        <view
          class="account-card__avatar"
          :style="{ background: preset.color }"
        >
          {{ preset.shortLabel }}
        </view>
        <view class="account-card__name-block">
          <text class="account-card__name">{{ account.alias }}</text>
          <text class="account-card__site">{{ account.siteName }} · {{ preset.label }}</text>
        </view>
      </view>
      <AccountStatusBadge :status="account.status" compact />
    </view>

    <view class="account-card__quota-row">
      <view>
        <text class="account-card__quota-label">当前可用额度</text>
        <text class="account-card__quota">{{ formatCurrency(account.quota) }}</text>
      </view>
      <svg class="account-card__arrow" viewBox="0 0 24 24" fill="none" aria-hidden="true">
        <path d="M9 6L15 12L9 18" />
      </svg>
    </view>

    <view class="account-card__meta">
      <view>
        <text class="account-card__meta-label">用户名</text>
        <text class="account-card__meta-value">{{ account.username || '未填写' }}</text>
      </view>
      <view>
        <text class="account-card__meta-label">API Key</text>
        <text class="account-card__meta-value">{{ keyCount }} 个</text>
      </view>
      <view>
        <text class="account-card__meta-label">{{ metaLabel }}</text>
        <text class="account-card__meta-value">{{ metaValue }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.account-card {
  padding: 26rpx;
  transition: transform 0.18s ease;

  &:active {
    transform: scale(0.99);
  }

  &--low {
    border-color: rgba(237, 138, 25, 0.22);
    box-shadow: 0 16rpx 40rpx rgba(237, 138, 25, 0.1);
  }

  &--expired {
    border-color: rgba(190, 38, 48, 0.2);
    box-shadow: 0 16rpx 40rpx rgba(190, 38, 48, 0.08);
  }

  &__head,
  &__identity,
  &__quota-row,
  &__meta {
    display: flex;
    align-items: center;
  }

  &__head,
  &__quota-row {
    justify-content: space-between;
  }

  &__identity {
    min-width: 0;
  }

  &__avatar {
    display: flex;
    width: 64rpx;
    height: 64rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 20rpx;
    color: #fff;
    font-size: 27rpx;
    font-weight: 800;
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
    font-size: 30rpx;
    font-weight: 750;
    line-height: 1.25;
  }

  &__site {
    overflow: hidden;
    margin-top: 5rpx;
    color: var(--yc-muted);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 21rpx;
  }

  &__quota-row {
    margin-top: 28rpx;
  }

  &__quota-label,
  &__meta-label,
  &__meta-value {
    display: block;
  }

  &__quota-label,
  &__meta-label {
    color: var(--yc-muted);
    font-size: 20rpx;
  }

  &__quota {
    display: block;
    margin-top: 4rpx;
    color: var(--yc-ink);
    font-size: 42rpx;
    font-weight: 800;
    letter-spacing: -1.4rpx;
    line-height: 1.12;
  }

  &__arrow {
    width: 36rpx;
    height: 36rpx;
    flex: none;
    stroke: var(--yc-muted);
    stroke-linecap: round;
    stroke-linejoin: round;
    stroke-width: 1.8;
  }

  &__meta {
    justify-content: space-between;
    gap: 14rpx;
    margin-top: 26rpx;
    padding-top: 20rpx;
    border-top: 1rpx solid var(--yc-line);
  }

  &__meta > view {
    min-width: 0;
    flex: 1;
  }

  &__meta > view:nth-child(2) {
    text-align: center;
  }

  &__meta > view:last-child {
    text-align: right;
  }

  &__meta-value {
    overflow: hidden;
    margin-top: 5rpx;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 20rpx;
    font-weight: 650;
  }
}
</style>
