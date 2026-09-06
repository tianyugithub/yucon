<script setup lang="ts">
import { computed } from 'vue'
import AccountCard from '@/components/AccountCard.vue'
import AppShell from '@/components/AppShell.vue'
import { NutButton, NutEmpty, NutSearchbar } from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import type { AccountStatus } from '@/types/domain'

const store = usePrototypeStore()

const statusFilters: Array<{ label: string; value: 'all' | AccountStatus }> = [
  { label: '全部', value: 'all' },
  { label: '正常', value: 'active' },
  { label: '低额度', value: 'low' },
  { label: '需登录', value: 'expired' }
]

const summaryText = computed(() => {
  const expired = store.expiredAccounts.length
  if (expired) {
    return `需重新登录 ${expired} 个，共 ${store.accounts.length} 个账号`
  }
  return `已正常 ${store.accounts.filter((account) => account.status === 'active').length} 个，共 ${store.accounts.length} 个账号`
})

const openAccount = (id: string): void => {
  uni.navigateTo({ url: `/pages/accounts/detail?id=${id}` })
}

const openCreate = (): void => {
  uni.navigateTo({ url: '/pages/accounts/form' })
}

const handleRefresh = async (): Promise<void> => {
  const refreshed = await store.refreshAllAccounts()
  if (refreshed) {
    store.notify('账号数据已从站点同步')
  }
}
</script>

<template>
  <AppShell :current-tab="1" title="账号" subtitle="连接并同步多个中转站点账号">
    <template #header-actions>
      <NutButton class="accounts__header-add" size="small" shape="round" custom-color="#fa2c19" @click="openCreate">
        添加账号
      </NutButton>
    </template>

    <template #header-extra>
      <view class="accounts__sticky">
        <view class="accounts__summary yc-card">
          <view>
            <text class="accounts__summary-label">已管理账号</text>
            <text class="accounts__summary-value">{{ store.accounts.length }}</text>
          </view>
          <text class="accounts__summary-copy">{{ summaryText }}</text>
        </view>

        <NutSearchbar
          v-model="store.searchTerm"
          class="accounts__search"
          placeholder="搜索备注、站点、用户名或类型"
          @search="handleRefresh"
        />

        <scroll-view class="accounts__filter-scroll" scroll-x>
          <view class="accounts__filters">
            <button
              v-for="filter in statusFilters"
              :key="filter.value"
              class="accounts__filter"
              :class="{ 'accounts__filter--active': store.selectedAccountStatus === filter.value }"
              @click="store.selectedAccountStatus = filter.value"
            >
              {{ filter.label }}
            </button>
          </view>
        </scroll-view>

        <view class="accounts__result-row">
          <text>共 {{ store.filteredAccounts.length }} 个账号</text>
          <button class="accounts__refresh" @click="handleRefresh">刷新</button>
        </view>
      </view>
    </template>

    <view class="yc-content accounts">
      <view v-if="store.filteredAccounts.length" class="accounts__list">
        <AccountCard
          v-for="account in store.filteredAccounts"
          :key="account.id"
          :account="account"
          :key-count="store.keyCountForAccount(account.id)"
          :checked-in="store.isCheckedInToday(account)"
          @open="openAccount(account.id)"
        />
      </view>
      <NutEmpty v-else description="没有匹配的账号" />

      <NutButton class="accounts__create" block shape="round" custom-color="#fa2c19" @click="openCreate">
        添加账号
      </NutButton>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.accounts {
  &__header-add {
    :deep(.nut-button) {
      height: 58rpx;
      padding: 0 18rpx;
      font-size: 21rpx;
      font-weight: 700;
    }
  }

  &__summary {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 26rpx;
    background:
      linear-gradient(120deg, rgba(49, 120, 223, 0.11), transparent 65%),
      var(--yc-surface);
  }

  &__summary-label,
  &__summary-value {
    display: block;
  }

  &__summary-label {
    color: var(--yc-muted);
    font-size: 22rpx;
  }

  &__summary-value {
    margin-top: 5rpx;
    color: var(--yc-ink);
    font-size: 44rpx;
    font-weight: 800;
    line-height: 1;
  }

  &__summary-copy {
    max-width: 300rpx;
    color: var(--yc-muted);
    text-align: right;
    font-size: 20rpx;
    line-height: 1.45;
  }

  &__search {
    margin-top: 22rpx;

    :deep(.nut-searchbar) {
      padding: 0;
    }

    :deep(.nut-searchbar__input) {
      height: 74rpx;
      border-radius: 22rpx;
      box-shadow: 0 10rpx 26rpx rgba(28, 32, 39, 0.04);
    }
  }

  &__filter-scroll {
    width: 100%;
    margin-top: 20rpx;
    white-space: nowrap;
  }

  &__filters {
    display: inline-flex;
    gap: 12rpx;
    padding: 0 2rpx;
  }

  &__filter {
    display: inline-flex;
    height: 58rpx;
    align-items: center;
    justify-content: center;
    margin: 0;
    padding: 0 20rpx;
    border: 1rpx solid transparent;
    border-radius: 999rpx;
    background: var(--yc-surface);
    color: var(--yc-muted);
    font-size: 22rpx;
    font-weight: 650;
    white-space: nowrap;

    &--active {
      border-color: rgba(250, 44, 25, 0.16);
      background: #fff0ed;
      color: $yc-primary;
    }
  }

  &__result-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin: 28rpx 2rpx 0;
    color: var(--yc-muted);
    font-size: 22rpx;
  }

  &__refresh {
    margin: 0;
    padding: 0;
    border: 0;
    border-radius: 0;
    background: transparent;
    color: $yc-primary;
    font-size: 22rpx;
    font-weight: 700;
    line-height: 1.45;
  }

  &__list {
    display: flex;
    flex-direction: column;
    gap: 18rpx;
  }

  &__create {
    margin-top: 28rpx;

    :deep(.nut-button) {
      height: 82rpx;
      font-size: 26rpx;
      font-weight: 750;
    }
  }
}
</style>
