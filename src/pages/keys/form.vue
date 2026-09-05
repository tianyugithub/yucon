<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import AppShell from '@/components/AppShell.vue'
import ModelBrandIcon from '@/components/ModelBrandIcon.vue'
import SelectSheet, { type SelectSheetOption } from '@/components/SelectSheet.vue'
import TabIcon from '@/components/TabIcon.vue'
import { detectModelBrand } from '@/constants/model-brands'
import { getPlatformPreset } from '@/constants/platform-presets'
import { NutButton, NutEmpty, NutInput, NutPopup, NutSwitch } from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import type { ApiKey } from '@/types/domain'
import { copyText } from '@/utils/clipboard'
import { getRouteParam } from '@/utils/route'

const store = usePrototypeStore()
const form = reactive(store.toApiKeyDraft())
const createdKey = ref<ApiKey | null>(null)
const showCreatedKey = ref(false)
const loadingOptions = ref(false)
const showGroupSheet = ref(false)
const showModelSheet = ref(false)
const showExpirySheet = ref(false)

onLoad((query) => {
  const id = getRouteParam(query, 'id')
  if (id) {
    const apiKey = store.apiKeyById(id)
    if (apiKey) {
      Object.assign(form, store.toApiKeyDraft(apiKey))
    }
  } else {
    const accountId = getRouteParam(query, 'accountId')
    if (accountId) {
      Object.assign(form, store.toApiKeyDraft(undefined, accountId))
    }
  }
  void loadOptions()
})

const isEditing = computed(() => Boolean(form.id))
const pageTitle = computed(() => (isEditing.value ? '编辑 Key' : '添加 Key'))
const boundAccount = computed(() =>
  form.accountId ? store.accountById(form.accountId) : undefined
)
const boundPreset = computed(() =>
  boundAccount.value ? getPlatformPreset(boundAccount.value.platformType) : undefined
)
const supportsModelLimits = computed(() => Boolean(boundPreset.value?.supportsKeyModelLimits))
const supportsCrossGroupRetry = computed(() => Boolean(boundPreset.value?.supportsCrossGroupRetry))
const isAccountExpired = computed(() => boundAccount.value?.status === 'expired')
const groupOptions = computed(() => store.groupsForAccount(boundAccount.value))
const selectedGroup = computed(() =>
  groupOptions.value.find((group) => group.name === form.group)
)
const selectedModels = computed(() =>
  form.modelLimitsText
    .split(/[\n,，]/)
    .map((item) => item.trim())
    .filter(Boolean)
)
const availableModels = computed(() =>
  form.accountId ? store.modelsForGroup(form.accountId, form.group) : []
)
const saving = ref(false)

const groupSheetOptions = computed((): SelectSheetOption[] =>
  groupOptions.value.map((group) => ({
    value: group.name,
    title: group.name,
    subtitle: group.desc,
    meta: group.ratioLabel
  }))
)

const modelSheetOptions = computed((): SelectSheetOption[] =>
  availableModels.value.map((name) => {
    const brand = detectModelBrand(name)
    return {
      value: name,
      title: name,
      subtitle: brand.label,
      icon: brand.key
    }
  })
)

const expirySheetOptions: SelectSheetOption[] = [
  { value: 'never', title: '永不过期', subtitle: '与站点控制台一致' },
  { value: 'month', title: '一个月后' },
  { value: 'day', title: '一天后' },
  { value: 'hour', title: '一小时后' }
]

const pad = (value: number): string => String(value).padStart(2, '0')

const formatLocalDate = (date: Date): string =>
  `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`

const formatLocalDateTime = (date: Date): string =>
  `${formatLocalDate(date)}T${pad(date.getHours())}:${pad(date.getMinutes())}`

const groupFieldLabel = computed(() =>
  selectedGroup.value
    ? `${selectedGroup.value.name} · ${selectedGroup.value.ratioLabel}`
    : form.group || '请选择分组'
)

const modelFieldLabel = computed(() =>
  selectedModels.value.length ? `已限制 ${selectedModels.value.length} 个模型` : '不限制模型'
)

const expiryFieldLabel = computed(() =>
  form.expiresAt ? form.expiresAt.replace('T', ' ') : '永不过期'
)

const loadOptions = async (): Promise<void> => {
  if (!form.accountId) {
    return
  }
  loadingOptions.value = true
  try {
    await store.loadTokenGroups(form.accountId)
    if (!isEditing.value) {
      form.group = store.defaultGroupForAccount(boundAccount.value)
    }
    if (supportsModelLimits.value) {
      await store.loadGroupModels(form.accountId, form.group)
    }
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '分组信息读取失败', 'warning')
  } finally {
    loadingOptions.value = false
  }
}

watch(
  () => form.group,
  async (group, previous) => {
    if (!form.accountId || !group || group === previous) {
      return
    }
    if (group !== 'auto') {
      form.crossGroupRetry = false
    }
    if (supportsModelLimits.value) {
      try {
        await store.loadGroupModels(form.accountId, group)
      } catch {
        return
      }
    }
  }
)

const applyExpiry = (preset: string): void => {
  const date = new Date()
  if (preset === 'never') {
    form.expiresAt = ''
    return
  }
  if (preset === 'month') {
    date.setMonth(date.getMonth() + 1)
    form.expiresAt = formatLocalDate(date)
    return
  }
  if (preset === 'day') {
    date.setDate(date.getDate() + 1)
    form.expiresAt = formatLocalDate(date)
    return
  }
  date.setHours(date.getHours() + 1)
  form.expiresAt = formatLocalDateTime(date)
}

const setModels = (values: string[]): void => {
  form.modelLimitsText = values.join(', ')
}

const copyCreatedKey = async (): Promise<void> => {
  if (!createdKey.value?.key) {
    store.notify('站点未返回完整 Key，请到详情页再试', 'warning')
    return
  }
  try {
    await copyText(createdKey.value.key)
    store.notify('API Key 已复制')
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '复制失败', 'error')
  }
}

const viewCreatedKey = (): void => {
  if (!createdKey.value) {
    return
  }
  showCreatedKey.value = false
  uni.redirectTo({ url: `/pages/keys/detail?id=${createdKey.value.id}` })
}

const goAccounts = (): void => {
  uni.reLaunch({ url: '/pages/accounts/index' })
}

const save = async (): Promise<void> => {
  if (!boundAccount.value) {
    store.notify('请先选择所属账号', 'warning')
    return
  }
  if (isAccountExpired.value) {
    store.notify('登录已过期，请先重新登录该账号', 'warning')
    return
  }
  if (!form.name.trim()) {
    store.notify('请填写 API Key 名称', 'warning')
    return
  }
  if (!form.group) {
    store.notify('请选择分组', 'warning')
    return
  }
  if (!form.unlimitedQuota) {
    const quota = Number(form.remainQuota.trim())
    if (!form.remainQuota.trim() || !Number.isFinite(quota) || quota < 0) {
      store.notify('请输入有效的额度', 'warning')
      return
    }
  }

  saving.value = true
  try {
    const apiKey = await store.saveApiKey(form)
    if (!apiKey) {
      store.notify('所属账号不存在', 'error')
      return
    }
    if (isEditing.value) {
      store.notify('API Key 配置已更新')
      uni.redirectTo({ url: `/pages/keys/detail?id=${apiKey.id}` })
      return
    }
    createdKey.value = apiKey
    showCreatedKey.value = true
  } catch (error) {
    store.notify(error instanceof Error ? error.message : '保存失败', 'error')
  } finally {
    saving.value = false
  }
}
</script>

<template>
  <AppShell
    v-if="boundAccount"
    :title="pageTitle"
    :subtitle="`${boundAccount.alias} 的 API Key`"
    show-back
    :back-url="`/pages/accounts/detail?id=${boundAccount.id}`"
  >
    <view class="yc-content key-form">
      <view class="key-form__tip">
        <view class="key-form__tip-icon">i</view>
        <text>{{
          isAccountExpired
            ? '该账号登录已过期，无法创建或修改 API Key。请先回到账号详情重新登录。'
            : supportsModelLimits
              ? '分组和模型来自当前站点。分组右侧的倍率与控制台一致，创建后站点通常只完整返回一次 Key。'
              : '该站点的 API Key 本身不限制模型，可用模型由分组决定。创建后站点通常只完整返回一次 Key。'
        }}</text>
      </view>

      <view class="key-form__preview yc-card">
        <view class="key-form__preview-icon">
          <TabIcon name="keys" />
        </view>
        <view>
          <text class="key-form__preview-title">{{ form.name || '未命名 Key' }}</text>
          <text class="key-form__preview-subtitle">
            {{ boundAccount.siteName }} · {{ groupFieldLabel }}
          </text>
        </view>
      </view>

      <view class="yc-section-title"><text>基础配置</text></view>
      <view class="key-form__card yc-card">
        <view class="key-form__field">
          <text class="key-form__label">Key 名称 <text class="key-form__required">*</text></text>
          <NutInput v-model="form.name" clearable placeholder="例如：生产环境、开发测试" />
        </view>

        <view class="key-form__switch-row">
          <view>
            <text class="key-form__label">无限额度</text>
            <text class="key-form__hint">开启后仅受用户总额度限制。</text>
          </view>
          <NutSwitch v-model="form.unlimitedQuota" active-color="#fa2c19" />
        </view>

        <view v-if="!form.unlimitedQuota" class="key-form__field">
          <text class="key-form__label">单 Key 额度 <text class="key-form__required">*</text></text>
          <NutInput v-model="form.remainQuota" type="digit" placeholder="例如：10.00" />
        </view>

        <view class="key-form__field key-form__field--last">
          <text class="key-form__label">有效期</text>
          <view class="key-form__select" @click="showExpirySheet = true">
            <text class="key-form__select-value">{{ expiryFieldLabel }}</text>
            <text class="key-form__select-arrow">▾</text>
          </view>
        </view>
      </view>

      <view class="yc-section-title">
        <text>调用权限</text>
        <text class="key-form__section-note">{{ loadingOptions ? '正在读取站点分组' : '按站点实时分组' }}</text>
      </view>
      <view class="key-form__card yc-card">
        <view class="key-form__field">
          <text class="key-form__label">分组 <text class="key-form__required">*</text></text>
          <view class="key-form__select" @click="showGroupSheet = true">
            <view class="key-form__select-copy">
              <text class="key-form__select-value">{{ selectedGroup?.name || form.group || '请选择分组' }}</text>
              <text class="key-form__select-sub">{{ selectedGroup?.desc || '从站点读取可用分组' }}</text>
            </view>
            <text class="key-form__select-meta">{{ selectedGroup?.ratioLabel || '▾' }}</text>
          </view>
          <text class="key-form__hint">
            {{ form.group === 'auto' ? 'auto 按系统自动分组规则路由，倍率随实际命中分组变化。' : '该倍率来自站点当前账号可见的分组配置。' }}
          </text>
        </view>

        <view v-if="supportsModelLimits" class="key-form__field">
          <text class="key-form__label">模型限制</text>
          <view class="key-form__select" @click="showModelSheet = true">
            <view v-if="selectedModels.length" class="key-form__brand-stack">
              <ModelBrandIcon
                v-for="name in selectedModels.slice(0, 3)"
                :key="name"
                :model="name"
                size="sm"
              />
            </view>
            <text class="key-form__select-value">{{ modelFieldLabel }}</text>
            <text class="key-form__select-arrow">▾</text>
          </view>
          <text class="key-form__hint">列表来自当前分组可用模型，不选表示不限制。</text>
        </view>
        <view v-else class="key-form__field">
          <text class="key-form__label">模型限制</text>
          <text class="key-form__hint">该平台的 Key 没有按模型限制，分组内可用模型都能调用。</text>
        </view>

        <view class="key-form__field">
          <text class="key-form__label">IP 白名单</text>
          <NutInput v-model="form.allowIpsText" placeholder="逗号或换行分隔；留空表示不限制" />
        </view>

        <view v-if="supportsCrossGroupRetry && form.group === 'auto'" class="key-form__switch-row key-form__switch-row--last">
          <view>
            <text class="key-form__label">跨分组重试</text>
            <text class="key-form__hint">仅 auto 分组可用，失败后允许改走其他自动分组。</text>
          </view>
          <NutSwitch v-model="form.crossGroupRetry" active-color="#fa2c19" />
        </view>
      </view>

      <NutButton
        class="key-form__save"
        block
        shape="round"
        custom-color="#fa2c19"
        :loading="saving"
        :disabled="isAccountExpired"
        @click="save"
      >
        {{ isEditing ? '保存配置' : '添加 API Key' }}
      </NutButton>
    </view>

    <SelectSheet
      :visible="showGroupSheet"
      title="选择分组"
      :options="groupSheetOptions"
      :model-value="form.group"
      searchable
      @update:visible="showGroupSheet = $event"
      @change="form.group = $event"
    />
    <SelectSheet
      v-if="supportsModelLimits"
      :visible="showModelSheet"
      title="选择可用模型"
      :options="modelSheetOptions"
      multiple
      searchable
      show-icons
      :selected-values="selectedModels"
      @update:visible="showModelSheet = $event"
      @confirm="setModels"
    />
    <SelectSheet
      :visible="showExpirySheet"
      title="选择有效期"
      :options="expirySheetOptions"
      :model-value="form.expiresAt ? 'custom' : 'never'"
      @update:visible="showExpirySheet = $event"
      @change="applyExpiry"
    />

    <NutPopup
      :visible="showCreatedKey"
      position="bottom"
      round
      closeable
      safe-area-inset-bottom
      @click-overlay="viewCreatedKey"
      @click-close-icon="viewCreatedKey"
    >
      <view v-if="createdKey" class="key-form__created-panel">
        <text class="key-form__created-title">API Key 创建成功</text>
        <text class="key-form__created-copy">这是唯一一次完整显示，请先复制后再关闭。</text>
        <view class="key-form__created-value">{{ createdKey.key }}</view>
        <NutButton block shape="round" custom-color="#fa2c19" @click="copyCreatedKey">复制 API Key</NutButton>
        <NutButton class="key-form__created-secondary" block plain shape="round" custom-color="#7d8490" @click="viewCreatedKey">
          查看详情
        </NutButton>
      </view>
    </NutPopup>
  </AppShell>

  <AppShell v-else title="添加 Key" subtitle="需从账号详情进入" show-back back-url="/pages/accounts/index">
    <view class="yc-content key-form__missing">
      <NutEmpty description="未指定所属账号" />
      <NutButton block shape="round" custom-color="#fa2c19" @click="goAccounts">
        返回账号列表
      </NutButton>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.key-form {
  &__tip {
    display: flex;
    align-items: flex-start;
    gap: 12rpx;
    margin: 6rpx 0 24rpx;
    padding: 19rpx 20rpx;
    border-radius: 20rpx;
    background: #fff0ed;
    color: #c54638;
    font-size: 21rpx;
    line-height: 1.5;
  }

  &__tip-icon {
    display: flex;
    width: 28rpx;
    height: 28rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    background: $yc-primary;
    color: #fff;
    font-size: 18rpx;
    font-weight: 800;
  }

  &__preview {
    display: flex;
    align-items: center;
    padding: 26rpx;
  }

  &__preview-icon {
    display: flex;
    width: 66rpx;
    height: 66rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    margin-right: 16rpx;
    border-radius: 21rpx;
    background: #3178df;
    color: #fff;

    :deep(.tab-icon) {
      width: 34rpx;
      height: 34rpx;
    }
  }

  &__preview-title,
  &__preview-subtitle {
    display: block;
  }

  &__preview-title {
    color: var(--yc-ink);
    font-size: 28rpx;
    font-weight: 750;
  }

  &__preview-subtitle {
    margin-top: 5rpx;
    color: var(--yc-muted);
    font-size: 20rpx;
  }

  &__card {
    overflow: hidden;
    padding: 4rpx 24rpx;
  }

  &__field {
    padding: 20rpx 0;

    :deep(.nut-input) {
      height: 72rpx;
      min-height: 72rpx;
      margin-top: 12rpx;
      padding: 0 20rpx;
      border: 1rpx solid #e6e9ee;
      border-radius: 16rpx;
      background: #f7f8fa;
      align-items: center;
    }

    :deep(.nut-input--border::after) {
      border-bottom: 0;
    }

    :deep(.nut-input__value) {
      display: flex;
      min-width: 0;
      align-items: center;
    }

    :deep(.nut-input__input),
    :deep(.uni-input-wrapper) {
      width: 100%;
    }

    :deep(.uni-input-wrapper) {
      display: flex;
      align-items: center;
    }

    :deep(.uni-input-input),
    :deep(.input-placeholder) {
      color: var(--yc-ink);
      font-size: 24rpx;
    }

    :deep(.input-placeholder) {
      color: #989fa9;
    }

    :deep(.nut-input__clear) {
      display: flex;
      height: 100%;
      align-items: center;
    }

    &--last {
      padding-bottom: 24rpx;
    }
  }

  &__select {
    display: flex;
    min-height: 72rpx;
    align-items: center;
    justify-content: space-between;
    gap: 16rpx;
    margin-top: 12rpx;
    padding: 14rpx 20rpx;
    border: 1rpx solid #e6e9ee;
    border-radius: 16rpx;
    background: #f7f8fa;
  }

  &__select-copy {
    min-width: 0;
    flex: 1;
  }

  &__select-value,
  &__select-sub,
  &__select-meta,
  &__select-arrow {
    display: block;
  }

  &__select-value {
    flex: 1;
    min-width: 0;
    overflow: hidden;
    color: var(--yc-ink);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 24rpx;
    font-weight: 650;
  }

  &__select-sub {
    margin-top: 4rpx;
    overflow: hidden;
    color: var(--yc-muted);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 18rpx;
  }

  &__select-meta {
    flex: none;
    color: $yc-primary;
    font-size: 24rpx;
    font-weight: 750;
  }

  &__select-arrow {
    color: var(--yc-muted);
    font-size: 22rpx;
  }

  &__brand-stack {
    display: flex;
    flex: none;
    align-items: center;

    :deep(.model-brand-icon) {
      box-shadow: 0 0 0 3rpx #f7f8fa;
    }

    :deep(.model-brand-icon + .model-brand-icon) {
      margin-left: -10rpx;
    }
  }

  &__label {
    display: block;
    color: var(--yc-ink);
    font-size: 24rpx;
    font-weight: 650;
  }

  &__required {
    color: $yc-primary;
  }

  &__hint {
    display: block;
    margin-top: 7rpx;
    color: var(--yc-muted);
    font-size: 20rpx;
    line-height: 1.45;
  }

  &__switch-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 20rpx;
    padding: 20rpx 0;
    border-top: 1rpx solid var(--yc-line);

    &--last {
      padding-bottom: 24rpx;
    }
  }

  &__section-note {
    color: var(--yc-muted);
    font-size: 20rpx;
    font-weight: 500;
  }

  &__save {
    margin-top: 42rpx;

    :deep(.nut-button) {
      height: 84rpx;
      font-size: 27rpx;
      font-weight: 750;
    }
  }

  &__created-panel {
    padding: 58rpx 34rpx calc(36rpx + env(safe-area-inset-bottom));
    background: var(--yc-surface);
  }

  &__created-title,
  &__created-copy {
    display: block;
    text-align: center;
  }

  &__created-title {
    color: var(--yc-ink);
    font-size: 34rpx;
    font-weight: 800;
  }

  &__created-copy {
    margin: 13rpx 0 26rpx;
    color: var(--yc-muted);
    font-size: 22rpx;
    line-height: 1.5;
  }

  &__created-value {
    overflow-x: auto;
    margin-bottom: 28rpx;
    padding: 22rpx;
    border-radius: 16rpx;
    background: #f3f5f7;
    color: var(--yc-ink);
    white-space: nowrap;
    font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
    font-size: 21rpx;
  }

  &__created-secondary {
    margin-top: 16rpx;
  }

  &__missing {
    padding-top: 100rpx;
  }
}
</style>
