<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import AppShell from '@/components/AppShell.vue'
import KeyStatusBadge from '@/components/KeyStatusBadge.vue'
import ModelBrandIcon from '@/components/ModelBrandIcon.vue'
import TabIcon from '@/components/TabIcon.vue'
import {
  NutButton,
  NutCell,
  NutCellGroup,
  NutEmpty,
  NutPopup,
  NutTag
} from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import { getPlatformPreset } from '@/constants/platform-presets'
import { formatCurrency, formatDateTime, formatShortDate, maskSecret } from '@/utils/format'
import { copyText } from '@/utils/clipboard'
import { getRouteParam } from '@/utils/route'

const store = usePrototypeStore()
const keyId = ref('')
const showValue = ref(false)
const showDeleteConfirm = ref(false)

onLoad((query) => {
  const id = getRouteParam(query, 'id')
  if (id) {
    keyId.value = id
  }
})

const apiKey = computed(() => (keyId.value ? store.apiKeyById(keyId.value) : undefined))
const owningAccount = computed(() =>
  apiKey.value ? store.accountById(apiKey.value.accountId) : undefined
)
const owningPreset = computed(() =>
  owningAccount.value ? getPlatformPreset(owningAccount.value.platformType) : undefined
)
const supportsModelLimits = computed(() => Boolean(owningPreset.value?.supportsKeyModelLimits))
const supportsCrossGroupRetry = computed(() => Boolean(owningPreset.value?.supportsCrossGroupRetry))

const quotaText = computed(() =>
  apiKey.value?.unlimitedQuota
    ? '无限额度'
    : formatCurrency(apiKey.value?.remainQuota ?? 0)
)

const expiryText = computed(() =>
  apiKey.value?.expiresAt ? formatShortDate(apiKey.value.expiresAt) : '永不过期'
)

const accessedText = computed(() =>
  apiKey.value?.accessedAt ? formatDateTime(apiKey.value.accessedAt) : '从未使用'
)

const ipText = computed(() =>
  apiKey.value?.allowIps.length ? apiKey.value.allowIps.join('、') : '不限制'
)

const editApiKey = (): void => {
  if (apiKey.value) {
    uni.navigateTo({ url: `/pages/keys/form?id=${apiKey.value.id}` })
  }
}

const openOwningAccount = (): void => {
  if (owningAccount.value) {
    uni.navigateTo({ url: `/pages/accounts/detail?id=${owningAccount.value.id}` })
  }
}

const copyKey = async (): Promise<void> => {
  if (!apiKey.value) {
    return
  }
  try {
    const value = await store.revealApiKey(apiKey.value.id)
    await copyText(value)
    store.notify('API Key 已复制')
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '复制失败', 'error')
  }
}

const revealValue = async (): Promise<void> => {
  if (!apiKey.value) {
    return
  }
  if (showValue.value) {
    showValue.value = false
    return
  }
  try {
    await store.revealApiKey(apiKey.value.id)
    showValue.value = true
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '无法显示完整 Key', 'error')
  }
}

const toggleStatus = async (): Promise<void> => {
  if (!apiKey.value) {
    return
  }
  try {
    const updated = await store.toggleApiKeyStatus(apiKey.value.id)
    if (!updated) {
      return
    }
    if (updated.status === 'expired' || updated.status === 'exhausted') {
      store.notify('已过期或耗尽的 Key 无法直接启用', 'warning')
      return
    }
    store.notify(updated.status === 'enabled' ? 'API Key 已启用' : 'API Key 已停用')
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '更新状态失败', 'error')
  }
}

const deleteApiKey = async (): Promise<void> => {
  if (!apiKey.value) {
    return
  }
  const accountId = apiKey.value.accountId
  try {
    await store.deleteApiKey(apiKey.value.id)
    store.notify('API Key 已删除')
    uni.reLaunch({ url: `/pages/accounts/detail?id=${accountId}` })
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '删除失败', 'error')
  }
}

const goAccounts = (): void => {
  uni.reLaunch({ url: '/pages/accounts/index' })
}
</script>

<template>
  <AppShell
    v-if="apiKey && owningAccount"
    title="Key 详情"
    :subtitle="`${owningAccount.alias} 的 API Key`"
    show-back
    :back-url="`/pages/accounts/detail?id=${owningAccount.id}`"
  >
    <template #header-actions>
      <button class="key-detail__edit" @click="editApiKey">编辑</button>
    </template>

    <view class="yc-content key-detail">
      <view class="key-detail__hero">
        <view class="key-detail__icon">
          <TabIcon name="keys" />
        </view>
        <view class="key-detail__identity">
          <view class="key-detail__name-row">
            <text class="key-detail__name">{{ apiKey.name }}</text>
            <KeyStatusBadge :status="apiKey.status" compact />
          </view>
          <text class="key-detail__subline">{{ owningAccount.siteName }} · {{ store.tokenGroupLabel(owningAccount.id, apiKey.group) }} · 最近使用：{{ accessedText }}</text>
        </view>
      </view>

      <view v-if="owningAccount.status === 'expired'" class="key-detail__expired yc-card">
        <text class="key-detail__expired-copy">所属账号登录已过期，显示或修改 Key 前请先重新登录。</text>
        <NutButton
          class="key-detail__expired-action"
          shape="round"
          custom-color="#fa2c19"
          @click="openOwningAccount"
        >
          去重新登录
        </NutButton>
      </view>

      <view class="key-detail__secret yc-card">
        <view class="key-detail__secret-main" @click="copyKey">
          <text class="key-detail__secret-label">API Key</text>
          <text class="key-detail__secret-value">{{ showValue ? apiKey.key : maskSecret(apiKey.key) }}</text>
        </view>
        <view class="key-detail__secret-actions">
          <button class="key-detail__secret-action" @click="revealValue">
            {{ showValue ? '隐藏' : '显示' }}
          </button>
          <button class="key-detail__secret-action" @click="copyKey">复制</button>
        </view>
      </view>

      <view class="key-detail__quota yc-card">
        <view>
          <text class="key-detail__quota-label">剩余额度</text>
          <text class="key-detail__quota-value">{{ quotaText }}</text>
        </view>
        <view class="key-detail__quota-meta">
          <text>已使用 {{ formatCurrency(apiKey.usedQuota) }}</text>
          <text>有效期 {{ expiryText }}</text>
        </view>
      </view>

      <view class="key-detail__actions">
        <NutButton
          class="key-detail__action"
          plain
          shape="round"
          custom-color="#fa2c19"
          @click="toggleStatus"
        >
          {{ apiKey.status === 'enabled' ? '停用 Key' : '启用 Key' }}
        </NutButton>
        <NutButton
          class="key-detail__action"
          shape="round"
          custom-color="#fa2c19"
          @click="editApiKey"
        >
          编辑配置
        </NutButton>
      </view>

      <view class="yc-section-title">
        <text>调用权限</text>
        <text class="key-detail__section-note">{{
          supportsModelLimits ? '来自站点 Token 配置' : '该平台 Key 不限制模型'
        }}</text>
      </view>
      <view class="key-detail__permissions yc-card">
        <NutCellGroup>
          <NutCell title="分组" :desc="store.tokenGroupLabel(owningAccount.id, apiKey.group)" />
          <NutCell title="IP 白名单" :desc="ipText" />
          <NutCell v-if="supportsCrossGroupRetry" title="跨分组重试">
            <template #desc>
              <NutTag
                round
                :custom-color="apiKey.crossGroupRetry ? '#e7f7ef' : '#eef0f3'"
                :text-color="apiKey.crossGroupRetry ? '#168553' : '#69707c'"
              >
                {{ apiKey.crossGroupRetry ? '已启用' : '未启用' }}
              </NutTag>
            </template>
          </NutCell>
        </NutCellGroup>
        <view v-if="supportsModelLimits" class="key-detail__models">
          <text class="key-detail__models-label">模型限制</text>
          <text v-if="!apiKey.modelLimits.length" class="key-detail__models-empty">不限制</text>
          <view v-else class="key-detail__model-list">
            <view v-for="name in apiKey.modelLimits" :key="name" class="key-detail__model">
              <ModelBrandIcon :model="name" size="sm" />
              <text>{{ name }}</text>
            </view>
          </view>
        </view>
        <view v-else class="key-detail__models">
          <text class="key-detail__models-label">模型限制</text>
          <text class="key-detail__models-empty">无，分组内模型均可调用</text>
        </view>
      </view>

      <NutButton
        class="key-detail__delete"
        block
        plain
        shape="round"
        custom-color="#e5484d"
        @click="showDeleteConfirm = true"
      >
        删除 API Key
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
      <view class="key-detail__delete-panel">
        <text class="key-detail__delete-title">删除这个 API Key？</text>
        <text class="key-detail__delete-copy">删除会直接作用到该站点上的 Token，删除后无法恢复。</text>
        <NutButton block shape="round" custom-color="#e5484d" @click="deleteApiKey">确认删除</NutButton>
        <NutButton
          class="key-detail__cancel"
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

  <AppShell v-else title="Key 详情" show-back back-url="/pages/accounts/index">
    <view class="yc-content key-detail__missing">
      <NutEmpty description="未找到该 API Key" />
      <NutButton block shape="round" custom-color="#fa2c19" @click="goAccounts">返回账号列表</NutButton>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.key-detail {
  &__edit,
  &__secret-action {
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

  &__icon {
    display: flex;
    width: 92rpx;
    height: 92rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 28rpx;
    background: #3178df;
    box-shadow: 0 12rpx 24rpx rgba(31, 111, 235, 0.2);
    color: #fff;

    :deep(.tab-icon) {
      width: 46rpx;
      height: 46rpx;
    }
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
    gap: 12rpx;
    margin-bottom: 22rpx;
    padding: 24rpx;
    border: 1rpx solid rgba(190, 38, 48, 0.16);
    background: #fff6f5;
  }

  &__expired-copy {
    color: #8a4a4f;
    font-size: 22rpx;
    line-height: 1.5;
  }

  &__expired-action {
    :deep(.nut-button) {
      height: 72rpx;
      font-size: 25rpx;
      font-weight: 750;
    }
  }

  &__secret {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20rpx;
    padding: 24rpx;
  }

  &__secret-main {
    min-width: 0;
    flex: 1;
  }

  &__secret-label,
  &__secret-value {
    display: block;
  }

  &__secret-label {
    color: var(--yc-muted);
    font-size: 20rpx;
  }

  &__secret-value {
    overflow: hidden;
    max-width: 370rpx;
    margin-top: 8rpx;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 22rpx;
    font-weight: 650;
  }

  &__secret-actions {
    display: flex;
    flex: none;
    flex-direction: column;
    gap: 12rpx;
    align-items: flex-end;
  }

  &__quota {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    margin-top: 18rpx;
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

  &__section-note {
    color: var(--yc-muted);
    font-size: 20rpx;
    font-weight: 500;
  }

  &__permissions {
    overflow: hidden;

    :deep(.nut-cell-group) {
      background: transparent;
    }

    :deep(.nut-cell) {
      min-height: 94rpx;
      align-items: center;
      padding: 18rpx 24rpx;
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
      color: var(--yc-muted);
      font-size: 21rpx;
    }

    :deep(.nut-tag) {
      border: 0;
      font-size: 19rpx;
    }
  }

  &__models {
    padding: 8rpx 24rpx 24rpx;
    border-top: 1rpx solid var(--yc-line);
  }

  &__models-label,
  &__models-empty {
    display: block;
  }

  &__models-label {
    padding: 16rpx 0 12rpx;
    color: var(--yc-ink);
    font-size: 24rpx;
    font-weight: 650;
  }

  &__models-empty {
    color: var(--yc-muted);
    font-size: 21rpx;
  }

  &__model-list {
    display: flex;
    flex-direction: column;
    gap: 10rpx;
  }

  &__model {
    display: flex;
    align-items: center;
    gap: 12rpx;
    min-width: 0;
    padding: 10rpx 12rpx;
    border-radius: 14rpx;
    background: #f7f8fa;

    text {
      overflow: hidden;
      color: var(--yc-ink);
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 22rpx;
      font-weight: 650;
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
