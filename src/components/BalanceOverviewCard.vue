<script setup lang="ts">
import { NutButton } from '@/components/nutui'
import { formatCurrency } from '@/utils/format'

withDefaults(
  defineProps<{
    totalQuota: number
    todayUsage: number
    accountCount: number
    checkinDone: number
    checkinTotal: number
    loading?: boolean
  }>(),
  {
    loading: false
  }
)

const emit = defineEmits<{
  refresh: []
  checkin: []
}>()
</script>

<template>
  <view class="balance-overview">
    <view class="balance-overview__glow balance-overview__glow--one" />
    <view class="balance-overview__glow balance-overview__glow--two" />
    <view class="balance-overview__content">
      <view class="balance-overview__headline">
        <view>
          <text class="balance-overview__eyebrow">全部账号可用额度</text>
          <text class="balance-overview__amount">{{ formatCurrency(totalQuota) }}</text>
        </view>
        <view class="balance-overview__vault">
          <text>钥</text>
        </view>
      </view>

      <view class="balance-overview__metrics">
        <view class="balance-overview__metric">
          <text class="balance-overview__metric-value">{{ formatCurrency(todayUsage) }}</text>
          <text class="balance-overview__metric-label">今日用量</text>
        </view>
        <view class="balance-overview__metric">
          <text class="balance-overview__metric-value">{{ accountCount }}</text>
          <text class="balance-overview__metric-label">管理账号</text>
        </view>
        <view class="balance-overview__metric">
          <text class="balance-overview__metric-value">{{
            checkinTotal ? `${checkinDone}/${checkinTotal}` : '—'
          }}</text>
          <text class="balance-overview__metric-label">今日签到</text>
        </view>
      </view>

      <view class="balance-overview__actions">
        <NutButton
          class="balance-overview__button balance-overview__button--secondary"
          shape="round"
          size="small"
          :loading="loading"
          @click="emit('refresh')"
        >
          刷新余额
        </NutButton>
        <NutButton
          v-if="checkinTotal > 0"
          class="balance-overview__button balance-overview__button--primary"
          shape="round"
          size="small"
          @click="emit('checkin')"
        >
          全部签到
        </NutButton>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.balance-overview {
  position: relative;
  overflow: hidden;
  border-radius: 32rpx;
  background:
    radial-gradient(circle at 92% 10%, rgba(255, 255, 255, 0.16), transparent 33%),
    linear-gradient(132deg, #1a1a1a 8%, #2f1814 48%, #fa2c19 156%);
  box-shadow: 0 24rpx 50rpx rgba(44, 28, 25, 0.24);
  color: #fff;

  &__content {
    position: relative;
    z-index: 1;
    padding: 34rpx 32rpx 30rpx;
  }

  &__glow {
    position: absolute;
    border-radius: 50%;
    opacity: 0.24;
    filter: blur(5rpx);

    &--one {
      width: 280rpx;
      height: 280rpx;
      top: -150rpx;
      right: -80rpx;
      background: #fa2c19;
    }

    &--two {
      width: 190rpx;
      height: 190rpx;
      bottom: -110rpx;
      left: 35%;
      background: #ffad9d;
    }
  }

  &__headline,
  &__metrics,
  &__actions {
    display: flex;
  }

  &__headline {
    align-items: flex-start;
    justify-content: space-between;
  }

  &__eyebrow,
  &__metric-label {
    display: block;
    color: rgba(255, 255, 255, 0.64);
    font-size: 22rpx;
    letter-spacing: 0.4rpx;
  }

  &__amount {
    display: block;
    margin-top: 8rpx;
    font-size: 60rpx;
    font-weight: 800;
    letter-spacing: -2rpx;
    line-height: 1;
  }

  &__vault {
    display: flex;
    width: 72rpx;
    height: 72rpx;
    align-items: center;
    justify-content: center;
    border: 1rpx solid rgba(255, 255, 255, 0.3);
    border-radius: 24rpx;
    background: rgba(255, 255, 255, 0.09);
    font-size: 34rpx;
    font-weight: 800;
  }

  &__metrics {
    margin-top: 36rpx;
    padding-top: 24rpx;
    border-top: 1rpx solid rgba(255, 255, 255, 0.18);
  }

  &__metric {
    display: flex;
    min-width: 0;
    flex: 1;
    flex-direction: column;

    & + & {
      padding-left: 24rpx;
      border-left: 1rpx solid rgba(255, 255, 255, 0.18);
    }
  }

  &__metric-value {
    font-size: 28rpx;
    font-weight: 750;
    line-height: 1.2;
  }

  &__metric-label {
    margin-top: 7rpx;
    font-size: 19rpx;
  }

  &__actions {
    gap: 16rpx;
    margin-top: 30rpx;
  }

  &__button {
    flex: 1;

    :deep(.nut-button) {
      height: 66rpx;
      border: 0;
      font-size: 23rpx;
      font-weight: 700;
    }

    &--secondary {
      :deep(.nut-button) {
        background: rgba(255, 255, 255, 0.14);
        color: #fff;
      }
    }

    &--primary {
      :deep(.nut-button) {
        background: #fff;
        color: $yc-primary;
      }
    }
  }
}
</style>
