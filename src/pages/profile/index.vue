<script setup lang="ts">
import { computed, ref } from 'vue'
import AppShell from '@/components/AppShell.vue'
import BrandMark from '@/components/BrandMark.vue'
import TabIcon from '@/components/TabIcon.vue'
import {
  NutButton,
  NutCell,
  NutCellGroup,
  NutInput,
  NutPopup,
  NutSwitch,
  NutTag
} from '@/components/nutui'
import { platformLabelSlash, summarizePlatformTypes } from '@/constants/platform-presets'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import { formatCurrency } from '@/utils/format'

type ProfilePanel = 'quota' | 'data' | 'about' | null

const store = usePrototypeStore()
const activePanel = ref<ProfilePanel>(null)
const quotaDraft = ref(store.settings.lowQuotaThreshold.toFixed(2))

const typeSummary = computed(() => summarizePlatformTypes(store.accounts))

const openPanel = (panel: Exclude<ProfilePanel, null>): void => {
  if (panel === 'quota') {
    quotaDraft.value = store.settings.lowQuotaThreshold.toFixed(2)
  }
  activePanel.value = panel
}

const closePanel = (): void => {
  activePanel.value = null
}

const saveQuotaThreshold = (): void => {
  const threshold = Number(quotaDraft.value)
  if (!Number.isFinite(threshold) || threshold < 0) {
    store.notify('请输入有效的额度阈值', 'error')
    return
  }
  store.updateSettings({ lowQuotaThreshold: threshold })
  store.notify('额度预警阈值已更新')
  closePanel()
}

const toggleNotifications = (): void => {
  store.notify(store.settings.notificationEnabled ? '额度通知已开启' : '额度通知已关闭', 'text')
}

const toggleIpLogs = (): void => {
  store.notify(store.settings.recordIpLog ? '将记录调用 IP' : '已停止记录调用 IP', 'text')
}

const toggleDarkMode = (): void => {
  store.notify(store.settings.darkMode ? '深色模式已开启' : '深色模式已关闭', 'text')
}
</script>

<template>
  <AppShell :current-tab="3" title="我的" subtitle="多账号同步与本地偏好">
    <view class="yc-content profile">
      <view class="profile__brand yc-card">
        <BrandMark
          class="profile__brand-logo"
          :size="94"
          :show-wordmark="true"
          :inverse="store.settings.darkMode"
        />
        <NutTag class="profile__brand-tag" round custom-color="#fff0ed" text-color="#d91d0d">
          {{ store.accounts.length ? '已连接站点' : '等待连接' }}
        </NutTag>
      </view>

      <view class="profile__vault yc-card">
        <view class="profile__vault-icon">
          <TabIcon name="accounts" />
        </view>
        <view class="profile__vault-copy">
          <text class="profile__vault-title">已管理 {{ store.accounts.length }} 个账号</text>
          <text class="profile__vault-subtitle">{{ typeSummary }}</text>
        </view>
      </view>

      <view class="yc-section-title"><text>管理概览</text></view>
      <view class="profile__cell-card yc-card">
        <NutCellGroup>
          <NutCell title="全部可用额度" :desc="formatCurrency(store.totalQuota)">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--red">￥</view>
            </template>
          </NutCell>
          <NutCell title="累计已用额度" :desc="formatCurrency(store.totalUsedQuota)">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--blue">
                <TabIcon name="logs" />
              </view>
            </template>
          </NutCell>
          <NutCell title="可用 API Key" :desc="`${store.activeApiKeyCount} 个`">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--green">
                <TabIcon name="keys" />
              </view>
            </template>
          </NutCell>
        </NutCellGroup>
      </view>

      <view class="yc-section-title"><text>本地偏好</text></view>
      <view class="profile__cell-card yc-card">
        <NutCellGroup>
          <NutCell
            title="额度预警"
            :desc="`低于 $${store.settings.lowQuotaThreshold.toFixed(2)} 时提醒`"
            is-link
            @click="openPanel('quota')"
          >
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--orange">!</view>
            </template>
          </NutCell>
          <NutCell title="额度通知">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--red">✓</view>
            </template>
            <template #desc>
              <NutSwitch
                v-model="store.settings.notificationEnabled"
                active-color="#fa2c19"
                @change="toggleNotifications"
              />
            </template>
          </NutCell>
          <NutCell title="记录调用 IP">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--blue">
                <TabIcon name="logs" />
              </view>
            </template>
            <template #desc>
              <NutSwitch
                v-model="store.settings.recordIpLog"
                active-color="#fa2c19"
                @change="toggleIpLogs"
              />
            </template>
          </NutCell>
          <NutCell title="深色模式">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--dark">◐</view>
            </template>
            <template #desc>
              <NutSwitch
                v-model="store.settings.darkMode"
                active-color="#fa2c19"
                @change="toggleDarkMode"
              />
            </template>
          </NutCell>
        </NutCellGroup>
      </view>

      <view class="yc-section-title"><text>数据与关于</text></view>
      <view class="profile__cell-card yc-card">
        <NutCellGroup>
          <NutCell title="本地数据说明" desc="会话保存在本机，资料来自站点同步" is-link @click="openPanel('data')">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--violet">
                <TabIcon name="accounts" />
              </view>
            </template>
          </NutCell>
          <NutCell title="关于 Yucon 钥仓" desc="多账号站点同步" is-link @click="openPanel('about')">
            <template #icon>
              <view class="profile__cell-icon profile__cell-icon--dark">Y</view>
            </template>
          </NutCell>
        </NutCellGroup>
      </view>
    </view>

    <NutPopup
      :visible="activePanel !== null"
      position="bottom"
      round
      closeable
      safe-area-inset-bottom
      @click-overlay="closePanel"
      @click-close-icon="closePanel"
    >
      <view class="profile__panel">
        <template v-if="activePanel === 'quota'">
          <text class="profile__panel-title">额度预警</text>
          <text class="profile__panel-desc">当任意账号的当前可用额度低于该值时显示提醒。</text>
          <view class="profile__form-row">
            <text>预警额度（美元）</text>
            <NutInput v-model="quotaDraft" type="digit" input-align="right" placeholder="5.00" />
          </view>
          <NutButton block shape="round" custom-color="#fa2c19" @click="saveQuotaThreshold">保存设置</NutButton>
        </template>

        <template v-else-if="activePanel === 'data'">
          <text class="profile__panel-title">本地数据说明</text>
          <text class="profile__panel-desc">账号列表、登录会话和最近同步结果保存在本机。密码只用于登录，不会写入存储。额度、API Key 和日志均从对应站点读取。</text>
          <NutTag round custom-color="#fff0ed" text-color="#d91d0d">不保存登录密码</NutTag>
        </template>

        <template v-else-if="activePanel === 'about'">
          <view class="profile__about-panel">
            <BrandMark :size="108" :show-wordmark="true" :inverse="store.settings.darkMode" />
            <text class="profile__panel-title">Yucon 钥仓</text>
            <text class="profile__panel-desc">连接 {{ platformLabelSlash }} 等中转站点，同步账号额度、API Key 和调用日志。</text>
            <NutTag round custom-color="#f1f3f6" text-color="#69707c">v0.1.0</NutTag>
          </view>
        </template>
      </view>
    </NutPopup>
  </AppShell>
</template>

<style scoped lang="scss">
.profile {
  &__brand {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20rpx;
    padding: 30rpx;
  }

  &__brand-logo {
    min-width: 0;
  }

  &__brand-tag {
    flex: none;
    border: 0;
    font-size: 19rpx;
  }

  &__vault {
    display: flex;
    align-items: center;
    margin-top: 20rpx;
    padding: 24rpx;
  }

  &__vault-icon {
    display: flex;
    width: 64rpx;
    height: 64rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 20rpx;
    background: linear-gradient(135deg, #fa2c19, #ff725e);
    color: #fff;

    :deep(.tab-icon) {
      width: 34rpx;
      height: 34rpx;
    }
  }

  &__vault-copy {
    display: flex;
    min-width: 0;
    flex-direction: column;
    margin-left: 16rpx;
  }

  &__vault-title {
    color: var(--yc-ink);
    font-size: 27rpx;
    font-weight: 750;
  }

  &__vault-subtitle {
    margin-top: 5rpx;
    color: var(--yc-muted);
    font-size: 19rpx;
  }

  &__cell-card {
    overflow: hidden;

    :deep(.nut-cell-group) {
      background: transparent;
    }

    :deep(.nut-cell) {
      min-height: 100rpx;
      align-items: center;
      padding: 18rpx 24rpx;
      background: transparent;
    }

    :deep(.nut-cell__title) {
      align-items: flex-start;
      justify-content: center;
      margin-left: 14rpx;
      color: var(--yc-ink);
      font-size: 25rpx;
      font-weight: 650;
    }

    :deep(.nut-cell__value) {
      display: flex;
      align-items: center;
      justify-content: flex-end;
      color: var(--yc-muted);
      font-size: 21rpx;
    }
  }

  &__cell-icon {
    display: flex;
    width: 48rpx;
    height: 48rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 16rpx;
    color: #fff;
    font-size: 23rpx;
    font-weight: 800;

    :deep(.tab-icon) {
      width: 28rpx;
      height: 28rpx;
    }

    &--red {
      background: #fa2c19;
    }

    &--blue {
      background: #3178df;
    }

    &--violet {
      background: #7c57dc;
    }

    &--orange {
      background: #ed8a19;
    }

    &--dark {
      background: #2d3036;
    }

    &--green {
      background: #1f9a68;
    }
  }

  &__panel {
    min-height: 330rpx;
    padding: 54rpx 34rpx calc(38rpx + env(safe-area-inset-bottom));
    background: var(--yc-surface);
  }

  &__panel-title,
  &__panel-desc {
    display: block;
  }

  &__panel-title {
    color: var(--yc-ink);
    font-size: 34rpx;
    font-weight: 800;
  }

  &__panel-desc {
    margin: 10rpx 0 28rpx;
    color: var(--yc-muted);
    font-size: 22rpx;
    line-height: 1.55;
  }

  &__form-row {
    display: flex;
    min-height: 86rpx;
    align-items: center;
    gap: 14rpx;
    margin-bottom: 28rpx;
    padding: 0 18rpx;
    border: 1rpx solid #e6e9ee;
    border-radius: 16rpx;
    background: #f7f8fa;
    color: var(--yc-ink);
    font-size: 24rpx;

    :deep(.nut-input) {
      min-width: 160rpx;
      flex: 1;
      padding: 0;
      background: transparent;
    }

    :deep(.nut-input--border::after) {
      border-bottom: 0;
    }
  }

  &__about-panel {
    display: flex;
    align-items: center;
    flex-direction: column;
    text-align: center;

    .profile__panel-title {
      margin-top: 24rpx;
    }
  }
}
</style>
