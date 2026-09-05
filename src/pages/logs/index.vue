<script setup lang="ts">
import { computed, ref } from 'vue'
import AppShell from '@/components/AppShell.vue'
import ModelBrandIcon from '@/components/ModelBrandIcon.vue'
import { getPlatformPreset } from '@/constants/platform-presets'
import { NutButton, NutEmpty, NutTag } from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import { formatCompactCount, formatCurrency, formatDateTime } from '@/utils/format'

type LogView = 'usage' | 'checkin'

const store = usePrototypeStore()
const activeView = ref<LogView>('usage')

const accountName = (accountId: string): string => {
  const account = store.accountById(accountId)
  return account ? store.displayAccountName(account) : '已删除账号'
}

const sortByNewest = <T extends { time: string }>(entries: T[]): T[] =>
  [...entries].sort(
    (first, second) =>
      new Date(second.time).getTime() - new Date(first.time).getTime()
  )

const checkinEntries = computed(() =>
  sortByNewest(store.checkinLogs).map((log) => ({
    ...log,
    accountName: accountName(log.accountId),
    typeLabel: getPlatformPreset(log.platformType).label
  }))
)

const usageEntries = computed(() =>
  sortByNewest(store.usageLogs).map((log) => ({
    ...log,
    accountName: accountName(log.accountId),
    typeLabel: getPlatformPreset(log.platformType).label
  }))
)

const handleCheckinAll = async (): Promise<void> => {
  const summary = store.summarizeCheckin(await store.checkinAll())
  store.notify(summary.message, summary.type)
}

const isActive = (view: LogView): boolean => activeView.value === view

const checkinResultText = (reward?: number): string =>
  typeof reward === 'number' ? `+${formatCurrency(reward)}` : '已完成'
</script>

<template>
  <AppShell :current-tab="2" title="日志" subtitle="调用与签到记录来自已连接账号">
    <template #header-actions>
      <NutButton
        v-if="store.todayCheckinStatus.total"
        class="logs__checkin-button"
        shape="round"
        size="small"
        custom-color="#fa2c19"
        @click="handleCheckinAll"
      >
        全部签到
      </NutButton>
    </template>

    <template #header-extra>
      <view class="logs__switcher yc-card">
        <button
          class="logs__switch"
          :class="{ 'logs__switch--active': isActive('usage') }"
          @click="activeView = 'usage'"
        >
          调用日志
          <text class="logs__switch-count">{{ formatCompactCount(usageEntries.length) }}</text>
        </button>
        <button
          class="logs__switch"
          :class="{ 'logs__switch--active': isActive('checkin') }"
          @click="activeView = 'checkin'"
        >
          签到记录
          <text class="logs__switch-count">{{ formatCompactCount(checkinEntries.length) }}</text>
        </button>
      </view>
    </template>

    <view class="yc-content logs">
      <view v-if="activeView === 'usage'" class="logs__list">
        <view v-for="log in usageEntries" :key="log.id" class="logs__item yc-card">
          <ModelBrandIcon class="logs__brand" :model="log.model" size="md" />
          <view class="logs__body">
            <view class="logs__item-top">
              <text class="logs__name">{{ log.model }}</text>
              <text class="logs__cost">-{{ formatCurrency(log.quotaCost) }}</text>
            </view>
            <text class="logs__message">{{ log.accountName }} · {{ log.apiKeyName }} · 输入 {{ log.promptTokens.toLocaleString() }} / 输出 {{ log.completionTokens.toLocaleString() }}</text>
            <view class="logs__meta">
              <text>{{ log.typeLabel }} · {{ log.success ? '调用成功' : '调用失败' }}</text>
              <text>{{ formatDateTime(log.time) }}</text>
            </view>
          </view>
        </view>
        <NutEmpty v-if="!usageEntries.length" description="暂无调用日志" />
      </view>

      <view v-else class="logs__list">
        <view v-for="log in checkinEntries" :key="log.id" class="logs__item yc-card">
          <view class="logs__icon" :class="{ 'logs__icon--failure': !log.success }">
            {{ log.success ? '✓' : '!' }}
          </view>
          <view class="logs__body">
            <view class="logs__item-top">
              <text class="logs__name">{{ log.accountName }}</text>
              <text class="logs__reward" :class="{ 'logs__reward--muted': !log.success }">
                {{ log.success ? checkinResultText(log.reward) : '已跳过' }}
              </text>
            </view>
            <text class="logs__message">{{ log.message }}</text>
            <view class="logs__meta">
              <text>{{ log.typeLabel }} · {{ log.success ? '签到成功' : '未获得额度' }}</text>
              <text>{{ formatDateTime(log.time) }}</text>
            </view>
          </view>
        </view>
        <NutEmpty v-if="!checkinEntries.length" description="暂无签到记录" />
      </view>

      <view class="logs__footer">
        <NutTag round plain type="primary">实时同步</NutTag>
        <text>记录来自各账号最近同步</text>
      </view>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.logs {
  &__checkin-button {
    :deep(.nut-button) {
      height: 58rpx;
      padding: 0 18rpx;
      font-size: 21rpx;
      font-weight: 700;
    }
  }

  &__switcher {
    display: flex;
    gap: 8rpx;
    padding: 8rpx;
  }

  &__switch {
    display: flex;
    height: 68rpx;
    min-width: 0;
    flex: 1;
    align-items: center;
    justify-content: center;
    gap: 9rpx;
    margin: 0;
    padding: 0;
    border: 0;
    border-radius: 18rpx;
    background: transparent;
    color: var(--yc-muted);
    font-size: 24rpx;
    font-weight: 700;
    line-height: 1.2;

    &--active {
      background: #fff0ed;
      color: $yc-primary;
    }
  }

  &__switch-count {
    display: inline-flex;
    min-width: 32rpx;
    height: 28rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    padding: 0 8rpx;
    border-radius: 999rpx;
    background: rgba(125, 132, 144, 0.14);
    color: inherit;
    font-size: 18rpx;
    font-variant-numeric: tabular-nums;
    line-height: 1;
  }

  &__switch--active &__switch-count {
    background: rgba(250, 44, 25, 0.12);
  }

  &__list {
    display: flex;
    flex-direction: column;
    gap: 16rpx;
    margin-top: 8rpx;
  }

  &__item {
    display: flex;
    align-items: flex-start;
    padding: 24rpx;
  }

  &__brand {
    flex: none;
    margin-top: 2rpx;
  }

  &__icon {
    display: flex;
    width: 54rpx;
    height: 54rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 18rpx;
    background: #e7f7ef;
    color: #168553;
    font-size: 28rpx;
    font-weight: 800;

    :deep(.tab-icon) {
      width: 30rpx;
      height: 30rpx;
    }

    &--failure {
      background: #fff0ed;
      color: $yc-primary;
    }

    &--usage {
      background: #edf4ff;
      color: #3178df;
    }
  }

  &__body {
    display: flex;
    min-width: 0;
    flex: 1;
    flex-direction: column;
    margin-left: 17rpx;
  }

  &__item-top,
  &__meta {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 18rpx;
  }

  &__name {
    overflow: hidden;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 26rpx;
    font-weight: 750;
  }

  &__reward {
    flex: none;
    color: #168553;
    font-size: 24rpx;
    font-weight: 750;

    &--muted {
      color: var(--yc-muted);
    }
  }

  &__cost {
    flex: none;
    color: $yc-primary;
    font-size: 24rpx;
    font-weight: 750;
  }

  &__message {
    overflow: hidden;
    margin-top: 7rpx;
    color: var(--yc-muted);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 21rpx;
  }

  &__meta {
    margin-top: 14rpx;
    color: #a0a5ad;
    font-size: 19rpx;
  }

  &__footer {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12rpx;
    margin: 34rpx 0 8rpx;
    color: var(--yc-muted);
    font-size: 19rpx;

    :deep(.nut-tag) {
      font-size: 18rpx;
    }
  }
}
</style>
