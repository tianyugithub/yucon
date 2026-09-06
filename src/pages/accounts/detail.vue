<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import AccountStatusBadge from '@/components/AccountStatusBadge.vue'
import ApiKeyCard from '@/components/ApiKeyCard.vue'
import AppShell from '@/components/AppShell.vue'
import QuotaTrend from '@/components/QuotaTrend.vue'
import { getPlatformPreset } from '@/constants/platform-presets'
import {
  NutButton,
  NutCell,
  NutCellGroup,
  NutEmpty,
  NutPopup,
  NutTag
} from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import { formatCurrency, formatDateTime } from '@/utils/format'
import { getRouteParam } from '@/utils/route'

const store = usePrototypeStore()
const accountId = ref('')
const showDeleteConfirm = ref(false)
const relogging = ref(false)

onLoad((query) => {
  const id = getRouteParam(query, 'id')
  if (id) {
    accountId.value = id
    void store.loadTokenGroups(id).catch(() => undefined)
  }
})

const account = computed(() =>
  accountId.value ? store.accountById(accountId.value) : undefined
)

const accountKeys = computed(() =>
  account.value ? store.apiKeysForAccount(account.value.id) : []
)

const preset = computed(() =>
  account.value ? getPlatformPreset(account.value.platformType) : undefined
)

const checkinText = computed(() => {
  if (!account.value?.checkinEnabled) {
    return '—'
  }
  if (store.isCheckedInToday(account.value)) {
    return '今日已签到'
  }
  return account.value.lastCheckin ? formatDateTime(account.value.lastCheckin) : '尚未签到'
})

const handleCheckin = async (): Promise<void> => {
  if (!account.value) {
    return
  }
  const result = await store.checkinAccount(account.value.id)
  if (result) {
    store.notify(result.message, result.success ? 'success' : 'warning')
  }
}

const editAccount = (): void => {
  if (account.value) {
    uni.navigateTo({ url: `/pages/accounts/form?id=${account.value.id}` })
  }
}

const addKey = (): void => {
  if (account.value) {
    uni.navigateTo({ url: `/pages/keys/form?accountId=${account.value.id}` })
  }
}

const openKey = (id: string): void => {
  uni.navigateTo({ url: `/pages/keys/detail?id=${id}` })
}

const deleteAccount = (): void => {
  if (!account.value) {
    return
  }
  store.deleteAccount(account.value.id)
  store.notify('账号及其本地会话已删除')
  uni.reLaunch({ url: '/pages/accounts/index' })
}

const handleSync = async (): Promise<void> => {
  if (!account.value) {
    return
  }
  try {
    await store.syncAccount(account.value.id)
    store.notify('账号已同步')
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '同步失败', 'error')
  }
}

const handleRelogin = async (): Promise<void> => {
  if (!account.value || relogging.value) {
    return
  }
  relogging.value = true
  try {
    const result = await store.reloginAccount(account.value.id)
    if (result === 'need-form') {
      uni.navigateTo({ url: `/pages/accounts/form?id=${account.value.id}` })
      return
    }
    store.notify('已重新登录并同步')
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '重新登录失败', 'error')
  } finally {
    relogging.value = false
  }
}

const goAccounts = (): void => {
  uni.reLaunch({ url: '/pages/accounts/index' })
}
</script>

<template>
  <AppShell
    v-if="account && preset"
    title="账号详情"
    :subtitle="`${preset.label} 用户资料`"
    show-back
    back-url="/pages/accounts/index"
  >
    <template #header-actions>
      <button class="account-detail__edit" @click="editAccount">编辑</button>
    </template>

    <view class="yc-content account-detail">
      <view class="account-detail__hero">
        <image
          class="account-detail__avatar"
          :src="preset.iconAsset"
          mode="aspectFill"
        />
        <view class="account-detail__identity">
          <view class="account-detail__name-row">
            <text class="account-detail__name">{{ account.alias }}</text>
            <AccountStatusBadge :status="account.status" compact />
          </view>
          <text class="account-detail__subline">{{ account.siteName }} · @{{ account.username || '未填写用户名' }}</text>
        </view>
      </view>

      <view v-if="account.status === 'expired'" class="account-detail__expired yc-card">
        <text class="account-detail__expired-title">登录已过期</text>
        <text class="account-detail__expired-copy">站点会话失效后无法同步额度、Key 和日志。请到编辑页填写用户名和密码后自动登录。</text>
        <NutButton
          class="account-detail__expired-action"
          shape="round"
          custom-color="#fa2c19"
          :loading="relogging"
          @click="handleRelogin"
        >
          去自动登录
        </NutButton>
      </view>

      <view class="account-detail__quota yc-card">
        <view>
          <text class="account-detail__quota-label">当前可用额度</text>
          <text class="account-detail__quota-value">{{ formatCurrency(account.quota) }}</text>
        </view>
        <view class="account-detail__quota-meta">
          <text>累计已用 {{ formatCurrency(account.usedQuota) }}</text>
          <text>累计请求 {{ account.requestCount.toLocaleString() }}</text>
        </view>
      </view>

      <view class="account-detail__actions">
        <NutButton
          class="account-detail__action"
          plain
          shape="round"
          custom-color="#fa2c19"
          @click="handleSync"
        >
          同步资料
        </NutButton>
        <NutButton
          v-if="account.checkinEnabled"
          class="account-detail__action"
          plain
          shape="round"
          custom-color="#fa2c19"
          @click="handleCheckin"
        >
          {{ store.isCheckedInToday(account) ? '今日已签到' : '立即签到' }}
        </NutButton>
        <NutButton class="account-detail__action" shape="round" custom-color="#fa2c19" :disabled="account.status === 'expired'" @click="addKey">
          添加 API Key
        </NutButton>
      </view>

      <view class="account-detail__trend yc-card">
        <QuotaTrend :points="account.trend" />
      </view>

      <view class="yc-section-title"><text>账号资料</text></view>
      <view class="account-detail__profile yc-card">
        <NutCellGroup>
          <NutCell title="站点地址" :desc="account.baseUrl" />
          <NutCell title="账号类型" :desc="preset.label" />
          <NutCell title="站点标识" :desc="account.siteName" />
          <NutCell title="用户名" :desc="account.username || '未填写'" />
          <NutCell title="用户 ID" :desc="account.userId || '未填写'" />
          <NutCell title="邮箱" :desc="account.email || '未填写'" />
          <NutCell title="默认分组" :desc="account.group || 'default'" />
          <NutCell v-if="account.checkinEnabled" title="最近签到" :desc="checkinText" />
          <NutCell title="最近同步" :desc="account.lastSyncedAt ? formatDateTime(account.lastSyncedAt) : '尚未同步'" />
          <NutCell v-if="account.lastError" title="最近错误" :desc="account.lastError" />
        </NutCellGroup>
      </view>

      <view class="yc-section-title">
        <text>API Key</text>
        <button class="yc-section-action" :disabled="account.status === 'expired'" @click="addKey">添加 Key</button>
      </view>
      <view v-if="accountKeys.length" class="account-detail__key-list">
        <ApiKeyCard
          v-for="apiKey in accountKeys"
          :key="apiKey.id"
          :api-key="apiKey"
          @open="openKey(apiKey.id)"
        />
      </view>
      <NutEmpty v-else description="该账号还没有 API Key" />

      <view v-if="account.tags.length" class="account-detail__tags">
        <NutTag
          v-for="tag in account.tags"
          :key="tag"
          round
          custom-color="#f1f3f6"
          text-color="#69707c"
        >
          {{ tag }}
        </NutTag>
      </view>

      <NutButton
        class="account-detail__delete"
        block
        plain
        shape="round"
        custom-color="#e5484d"
        @click="showDeleteConfirm = true"
      >
        删除账号
      </NutButton>
    </view>

    <NutPopup
      :visible="showDeleteConfirm"
      position="bottom"
      round
      closeable
      safe-area-inset-bottom
      @click-overlay="showDeleteConfirm = false"
      @click-close-icon="showDeleteConfirm = false"
    >
      <view class="account-detail__delete-panel">
        <text class="account-detail__delete-title">删除这个账号？</text>
        <text class="account-detail__delete-copy">该账号下的本地 API Key、签到和调用记录会一并删除。</text>
        <NutButton block shape="round" custom-color="#e5484d" @click="deleteAccount">确认删除</NutButton>
        <NutButton
          class="account-detail__cancel"
          block
          plain
          shape="round"
          custom-color="#7d8490"
          @click="showDeleteConfirm = false"
        >
          取消
        </NutButton>
      </view>
    </NutPopup>
  </AppShell>

  <AppShell v-else title="账号详情" show-back back-url="/pages/accounts/index">
    <view class="yc-content account-detail__missing">
      <NutEmpty description="未找到该账号" />
      <NutButton block shape="round" custom-color="#fa2c19" @click="goAccounts">返回账号列表</NutButton>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.account-detail {
  &__edit {
    margin: 0;
    padding: 0;
    border: 0;
    border-radius: 0;
    background: transparent;
    color: $yc-primary;
    font-size: 24rpx;
    font-weight: 700;
    line-height: 1.3;
  }

  &__hero {
    display: flex;
    align-items: center;
    margin: 10rpx 0 26rpx;
  }

  &__avatar {
    display: flex;
    width: 92rpx;
    height: 92rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 28rpx;
    overflow: hidden;
    box-shadow: 0 12rpx 24rpx rgba(10, 16, 28, 0.16);
  }

  &__identity {
    display: flex;
    min-width: 0;
    flex: 1;
    flex-direction: column;
    margin-left: 20rpx;
  }

  &__name-row {
    display: flex;
    align-items: center;
    gap: 14rpx;
  }

  &__name {
    overflow: hidden;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 36rpx;
    font-weight: 800;
    letter-spacing: -1rpx;
  }

  &__subline {
    overflow: hidden;
    margin-top: 8rpx;
    color: var(--yc-muted);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 21rpx;
  }

  &__expired {
    display: flex;
    flex-direction: column;
    gap: 10rpx;
    margin-bottom: 22rpx;
    padding: 24rpx;
    border: 1rpx solid rgba(190, 38, 48, 0.16);
    background: #fff6f5;
  }

  &__expired-title,
  &__expired-copy {
    display: block;
  }

  &__expired-title {
    color: #be2630;
    font-size: 28rpx;
    font-weight: 750;
  }

  &__expired-copy {
    color: #8a4a4f;
    font-size: 22rpx;
    line-height: 1.5;
  }

  &__expired-action {
    margin-top: 8rpx;

    :deep(.nut-button) {
      height: 72rpx;
      font-size: 25rpx;
      font-weight: 750;
    }
  }

  &__quota {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    padding: 30rpx;
    background:
      linear-gradient(120deg, rgba(250, 44, 25, 0.11), transparent 62%),
      var(--yc-surface);
  }

  &__quota-label,
  &__quota-value {
    display: block;
  }

  &__quota-label {
    color: var(--yc-muted);
    font-size: 22rpx;
  }

  &__quota-value {
    margin-top: 8rpx;
    color: var(--yc-ink);
    font-size: 52rpx;
    font-weight: 800;
    letter-spacing: -2rpx;
    line-height: 1;
  }

  &__quota-meta {
    display: flex;
    flex-direction: column;
    gap: 7rpx;
    color: var(--yc-muted);
    text-align: right;
    font-size: 20rpx;
  }

  &__actions {
    display: flex;
    flex-wrap: wrap;
    gap: 16rpx;
    margin-top: 22rpx;
  }

  &__action {
    flex: 1;

    :deep(.nut-button) {
      height: 78rpx;
      font-size: 25rpx;
      font-weight: 750;
    }
  }

  &__trend {
    margin-top: 22rpx;
    padding: 26rpx;
  }

  &__profile {
    overflow: hidden;

    :deep(.nut-cell-group) {
      background: transparent;
    }

    :deep(.nut-cell) {
      min-height: 90rpx;
      align-items: center;
      padding: 16rpx 24rpx;
      background: transparent;
    }

    :deep(.nut-cell__title) {
      align-items: flex-start;
      justify-content: center;
      color: var(--yc-ink);
      font-size: 24rpx;
      font-weight: 650;
    }

    :deep(.nut-cell__value) {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      max-width: 350rpx;
      color: var(--yc-muted);
      font-size: 21rpx;
      text-align: right;
    }
  }

  &__key-list {
    display: flex;
    flex-direction: column;
    gap: 18rpx;
  }

  &__tags {
    display: flex;
    flex-wrap: wrap;
    gap: 10rpx;
    margin-top: 22rpx;

    :deep(.nut-tag) {
      border: 0;
      font-size: 19rpx;
    }
  }

  &__delete {
    margin-top: 28rpx;

    :deep(.nut-button) {
      height: 78rpx;
      font-size: 25rpx;
      font-weight: 700;
    }
  }

  &__delete-panel {
    padding: 60rpx 34rpx calc(36rpx + env(safe-area-inset-bottom));
    background: var(--yc-surface);
  }

  &__delete-title,
  &__delete-copy {
    display: block;
    text-align: center;
  }

  &__delete-title {
    color: var(--yc-ink);
    font-size: 34rpx;
    font-weight: 800;
  }

  &__delete-copy {
    margin: 13rpx 0 32rpx;
    color: var(--yc-muted);
    font-size: 22rpx;
    line-height: 1.5;
  }

  &__cancel {
    margin-top: 16rpx;
  }

  &__missing {
    padding-top: 100rpx;
  }
}
</style>
