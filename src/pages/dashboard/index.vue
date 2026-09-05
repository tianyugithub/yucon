<script setup lang="ts">
import { computed } from 'vue'
import AccountCard from '@/components/AccountCard.vue'
import AppShell from '@/components/AppShell.vue'
import BalanceOverviewCard from '@/components/BalanceOverviewCard.vue'
import TabIcon from '@/components/TabIcon.vue'
import { NutButton, NutEmpty, NutTag } from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import { copyText } from '@/utils/clipboard'

const store = usePrototypeStore()
const recentAccounts = computed(() => store.accounts.slice(0, 3))

const statusMessage = computed(() => {
  if (!store.accounts.length) {
    return '还没有连接账号'
  }
  if (store.expiredAccounts.length) {
    return `${store.expiredAccounts.length} 个账号登录已过期，需要重新登录`
  }
  return store.lowQuotaAccounts.length
    ? `${store.lowQuotaAccounts.length} 个账号低于额度预警阈值`
    : '全部账号额度状态正常'
})

const healthDescription = computed(() => {
  if (!store.accounts.length) {
    return '添加站点账号后即可同步额度和 Key'
  }
  if (store.expiredAccounts.length) {
    return '打开账号详情即可重新登录并换发令牌'
  }
  return store.lowQuotaAccounts.length
    ? `预警阈值：${store.settings.lowQuotaThreshold.toFixed(2)} 美元`
    : `${store.activeApiKeyCount} 个 API Key 可正常调用`
})

const handleRefresh = async (): Promise<void> => {
  const refreshed = await store.refreshAllAccounts()
  if (refreshed) {
    store.notify('账号额度已从站点同步')
  }
}

const handleCheckin = async (): Promise<void> => {
  const summary = store.summarizeCheckin(await store.checkinAll())
  store.notify(summary.message, summary.type)
}

const openAccount = (id: string): void => {
  uni.navigateTo({ url: `/pages/accounts/detail?id=${id}` })
}

const openAccounts = (): void => {
  uni.reLaunch({ url: '/pages/accounts/index' })
}

const openCreate = (): void => {
  uni.navigateTo({ url: '/pages/accounts/form' })
}

const openLogs = (): void => {
  uni.reLaunch({ url: '/pages/logs/index' })
}

const copyFirstKey = async (): Promise<void> => {
  const apiKey = store.apiKeys.find((key) => key.status === 'enabled')
  if (!apiKey) {
    store.notify('没有可复制的启用 Key', 'warning')
    return
  }
  try {
    const value = await store.revealApiKey(apiKey.id)
    await copyText(value)
    store.notify(`${apiKey.name} 已复制`)
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '复制失败', 'error')
  }
}
</script>

<template>
  <AppShell :current-tab="0">
    <template #header-actions>
      <NutButton class="dashboard__header-action" size="small" shape="round" custom-color="#fa2c19" @click="openCreate">
        添加账号
      </NutButton>
    </template>

    <view class="yc-content dashboard">
      <view class="dashboard__welcome">
        <view>
          <text class="dashboard__greeting">你的 API 账号，集中守护</text>
          <text class="dashboard__caption">多账号实时同步</text>
        </view>
        <NutTag round custom-color="#fff0ed" text-color="#d91d0d">{{ store.accounts.length }} 个账号</NutTag>
      </view>

      <BalanceOverviewCard
        :total-quota="store.totalQuota"
        :today-usage="store.todayUsage"
        :account-count="store.accounts.length"
        :checkin-done="store.todayCheckinStatus.done"
        :checkin-total="store.todayCheckinStatus.total"
        :loading="store.isRefreshing"
        @refresh="handleRefresh"
        @checkin="handleCheckin"
      />

      <view class="dashboard__health yc-card">
        <view
          class="dashboard__health-icon"
          :class="{
            'dashboard__health-icon--warning': store.expiredAccounts.length || store.lowQuotaAccounts.length
          }"
        >
          {{ store.expiredAccounts.length || store.lowQuotaAccounts.length ? '!' : '✓' }}
        </view>
        <view class="dashboard__health-copy">
          <text class="dashboard__health-title">{{ statusMessage }}</text>
          <text class="dashboard__health-desc">{{ healthDescription }}</text>
        </view>
      </view>

      <view class="yc-section-title">
        <text>快捷操作</text>
      </view>
      <view class="dashboard__quick-grid">
        <button v-if="store.todayCheckinStatus.total" class="dashboard__quick-item" @click="handleCheckin">
          <view class="dashboard__quick-icon dashboard__quick-icon--red">✓</view>
          <text>快速签到</text>
        </button>
        <button class="dashboard__quick-item" @click="copyFirstKey">
          <view class="dashboard__quick-icon dashboard__quick-icon--dark">
            <TabIcon name="keys" />
          </view>
          <text>复制 Key</text>
        </button>
        <button class="dashboard__quick-item" @click="openCreate">
          <view class="dashboard__quick-icon dashboard__quick-icon--blue">＋</view>
          <text>添加账号</text>
        </button>
        <button class="dashboard__quick-item" @click="openLogs">
          <view class="dashboard__quick-icon dashboard__quick-icon--violet">
            <TabIcon name="logs" />
          </view>
          <text>调用日志</text>
        </button>
      </view>

      <view class="yc-section-title">
        <text>最近账号</text>
        <button class="yc-section-action" @click="openAccounts">查看全部</button>
      </view>
      <view v-if="recentAccounts.length" class="dashboard__account-list">
        <AccountCard
          v-for="account in recentAccounts"
          :key="account.id"
          :account="account"
          :key-count="store.keyCountForAccount(account.id)"
          :checked-in="store.isCheckedInToday(account)"
          @open="openAccount(account.id)"
        />
      </view>
      <NutEmpty v-else description="还没有添加账号" />

      <NutButton
        class="dashboard__manage-accounts"
        block
        plain
        shape="round"
        custom-color="#fa2c19"
        @click="openAccounts"
      >
        管理账号
      </NutButton>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.dashboard {
  &__header-action {
    :deep(.nut-button) {
      height: 58rpx;
      padding: 0 18rpx;
      font-size: 21rpx;
      font-weight: 700;
    }
  }

  &__welcome {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8rpx 2rpx 24rpx;

    :deep(.nut-tag) {
      padding: 7rpx 12rpx;
      border: 0;
      font-size: 20rpx;
      font-weight: 700;
    }
  }

  &__greeting,
  &__caption {
    display: block;
  }

  &__greeting {
    color: var(--yc-ink);
    font-size: 30rpx;
    font-weight: 750;
  }

  &__caption {
    margin-top: 6rpx;
    color: var(--yc-muted);
    font-size: 21rpx;
  }

  &__health {
    display: flex;
    align-items: center;
    margin-top: 22rpx;
    padding: 22rpx 24rpx;
  }

  &__health-icon {
    display: flex;
    width: 48rpx;
    height: 48rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 16rpx;
    background: #e7f7ef;
    color: #168553;
    font-size: 27rpx;
    font-weight: 800;

    &--warning {
      background: #fff0ed;
      color: $yc-primary;
    }
  }

  &__health-copy {
    display: flex;
    min-width: 0;
    flex: 1;
    flex-direction: column;
    margin-left: 16rpx;
  }

  &__health-title {
    overflow: hidden;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 25rpx;
    font-weight: 700;
  }

  &__health-desc {
    margin-top: 5rpx;
    color: var(--yc-muted);
    font-size: 20rpx;
  }

  &__quick-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: 16rpx;
  }

  &__quick-item {
    display: flex;
    min-width: 0;
    align-items: center;
    flex-direction: column;
    gap: 11rpx;
    margin: 0;
    padding: 20rpx 4rpx;
    border: 0;
    border-radius: 22rpx;
    background: var(--yc-surface);
    box-shadow: 0 10rpx 26rpx rgba(28, 32, 39, 0.04);
    color: var(--yc-ink);
    font-size: 20rpx;
    font-weight: 650;
    line-height: 1.25;
  }

  &__quick-icon {
    display: flex;
    width: 56rpx;
    height: 56rpx;
    align-items: center;
    justify-content: center;
    border-radius: 18rpx;
    color: #fff;
    font-size: 30rpx;
    font-weight: 800;

    :deep(.tab-icon) {
      width: 30rpx;
      height: 30rpx;
    }

    &--red {
      background: linear-gradient(135deg, #fa2c19, #ff725e);
    }

    &--dark {
      background: #25272b;
    }

    &--blue {
      background: #3178df;
    }

    &--violet {
      background: #8257e6;
    }
  }

  &__account-list {
    display: flex;
    flex-direction: column;
    gap: 18rpx;
  }

  &__manage-accounts {
    margin-top: 22rpx;

    :deep(.nut-button) {
      height: 78rpx;
      background: transparent;
      font-size: 25rpx;
      font-weight: 700;
    }
  }
}
</style>
