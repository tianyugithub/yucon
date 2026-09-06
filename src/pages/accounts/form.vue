<script setup lang="ts">
import { computed, reactive, ref, watch } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import { fetchPublicSettings, type Sub2PublicSettings } from '@/api/sub2api'
import { fetchSiteStatus } from '@/api/newapi'
import { detectSitePlatform } from '@/api/site-detect'
import AppShell from '@/components/AppShell.vue'
import TurnstileWidget from '@/components/TurnstileWidget.vue'
import { tagOptions } from '@/constants/demo-data'
import { getPlatformPreset, platformTypeOptions } from '@/constants/platform-presets'
import { NutButton, NutInput } from '@/components/nutui'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import type { AccountDraft, AuthMode, PlatformType } from '@/types/domain'
import { getRouteParam } from '@/utils/route'

const store = usePrototypeStore()
const form = reactive<AccountDraft>(store.toAccountDraft())
const saving = ref(false)
const capturing = ref(false)
const turnstileToken = ref('')
const turnstileReset = ref(0)
const turnstileBlocked = ref(false)
const sub2Settings = ref<Sub2PublicSettings | null>(null)
const sub2SettingsError = ref('')
const probingSite = ref(false)
let probeTimer: ReturnType<typeof setTimeout> | undefined
let userPickedPlatform = false

onLoad((query) => {
  const id = getRouteParam(query, 'id')
  if (!id) {
    return
  }
  const account = store.accountById(id)
  if (account) {
    Object.assign(form, store.toAccountDraft(account))
    userPickedPlatform = true
    if (!getPlatformPreset(form.platformType).supportsAccessToken) {
      form.authMode = 'password'
    }
  }
})

const isEditing = computed(() => Boolean(form.id))
const editingExpired = computed(() => {
  if (!form.id) {
    return false
  }
  return store.accountById(form.id)?.status === 'expired'
})
const pageTitle = computed(() =>
  editingExpired.value ? '重新登录' : isEditing.value ? '编辑账号' : '添加账号'
)
const selectedPreset = computed(() => getPlatformPreset(form.platformType))
const supportsAccessToken = computed(() => selectedPreset.value.supportsAccessToken)
const previewHost = computed(() => form.baseUrl.replace(/^https?:\/\//, '').replace(/\/$/, '') || '未填写站点地址')
const isSub2Api = computed(() => form.platformType === 'sub2api')
const usePasswordLogin = computed(
  () => form.authMode === 'password' || !supportsAccessToken.value
)
const needsTurnstile = computed(() => {
  if (!usePasswordLogin.value) {
    return false
  }
  if (!isSub2Api.value || !sub2Settings.value?.turnstile_enabled || !sub2Settings.value.turnstile_site_key) {
    return false
  }
  return !isEditing.value || Boolean(form.password)
})

type AuthStage = 'checking' | 'captcha' | 'submitting'
const authOverlay = ref(false)
const authStage = ref<AuthStage>('checking')
const authDetail = ref('')
const authError = ref('')
const loginSteps: Array<{ id: AuthStage; title: string; subtitle: string }> = [
  { id: 'checking', title: '检查站点设置', subtitle: '读取人机验证等公开配置' },
  { id: 'captcha', title: '过站点人机验证', subtitle: '完成 Cloudflare Turnstile 或由验证码服务代解' },
  { id: 'submitting', title: '提交登录', subtitle: '用账号和密码调用站点登录接口' }
]

const dismissAuthProgress = (): void => {
  authOverlay.value = false
  authError.value = ''
  authDetail.value = ''
  authStage.value = 'checking'
}

const authStepState = (index: number): 'done' | 'active' | 'error' | 'pending' => {
  const currentIndex = loginSteps.findIndex((item) => item.id === authStage.value)
  if (authError.value && index === currentIndex) {
    return 'error'
  }
  if (currentIndex > index) {
    return 'done'
  }
  if (currentIndex === index) {
    return 'active'
  }
  return 'pending'
}

const applyPlatform = (type: PlatformType): void => {
  form.platformType = type
  if (!getPlatformPreset(type).supportsAccessToken && form.authMode === 'access_token') {
    form.authMode = 'password'
    form.accessToken = ''
  }
}

const probeSite = async (): Promise<void> => {
  const baseUrl = form.baseUrl.trim()
  if (!baseUrl) {
    sub2Settings.value = null
    sub2SettingsError.value = ''
    turnstileToken.value = ''
    turnstileBlocked.value = false
    return
  }
  probingSite.value = true
  sub2SettingsError.value = ''
  try {
    if (!isEditing.value && !userPickedPlatform) {
      const detected = await detectSitePlatform(baseUrl)
      if (detected && !userPickedPlatform) {
        applyPlatform(detected.type)
        if (detected.siteName && !form.siteName.trim()) {
          form.siteName = detected.siteName
        }
      }
    }
    if (form.platformType === 'sub2api') {
      sub2Settings.value = await fetchPublicSettings(baseUrl)
      if (sub2Settings.value.site_name && !form.siteName.trim()) {
        form.siteName = sub2Settings.value.site_name
      }
    } else {
      sub2Settings.value = null
      turnstileToken.value = ''
      turnstileBlocked.value = false
      const status = await fetchSiteStatus(baseUrl)
      if (status.systemName && !form.siteName.trim()) {
        form.siteName = status.systemName
      }
    }
  } catch (error) {
    if (form.platformType === 'sub2api') {
      sub2Settings.value = null
      sub2SettingsError.value = error instanceof Error ? error.message : '无法读取站点设置'
    }
  } finally {
    probingSite.value = false
  }
}

watch(
  () => form.baseUrl,
  () => {
    userPickedPlatform = false
    if (probeTimer) {
      clearTimeout(probeTimer)
    }
    probeTimer = setTimeout(() => {
      void probeSite()
    }, 400)
  }
)

const toggleTag = (tag: string): void => {
  form.tags = form.tags.includes(tag)
    ? form.tags.filter((item) => item !== tag)
    : [...form.tags, tag]
}

const selectPlatform = (type: PlatformType): void => {
  userPickedPlatform = true
  applyPlatform(type)
  void probeSite()
}

const setAuthMode = (mode: AuthMode): void => {
  if (mode === 'access_token' && !supportsAccessToken.value) {
    return
  }
  form.authMode = mode
}

const save = async (): Promise<void> => {
  if (!form.baseUrl.trim()) {
    store.notify('请填写站点地址', 'warning')
    return
  }
  if (!supportsAccessToken.value) {
    form.authMode = 'password'
  }
  if (form.authMode === 'password') {
    const hasJwtFallback = isSub2Api.value && Boolean(form.accessToken.trim())
    if (editingExpired.value && !hasJwtFallback && !form.password) {
      store.notify(`登录已过期，请填写${selectedPreset.value.identityLabel}和密码后自动登录`, 'warning')
      return
    }
    if (!hasJwtFallback && (!form.username.trim() || (!isEditing.value && !form.password))) {
      store.notify(
        isEditing.value
          ? `请填写${selectedPreset.value.identityLabel}；若需重新登录请同时填写密码`
          : `请填写${selectedPreset.value.identityLabel}和密码`,
        'warning'
      )
      return
    }
  } else if (form.authMode === 'access_token') {
    if ((!isEditing.value || editingExpired.value) && !form.accessToken.trim()) {
      store.notify(editingExpired.value ? '登录已过期，请填写新的访问令牌' : '请填写系统访问令牌', 'warning')
      return
    }
    if (!form.userId.trim()) {
      store.notify('请填写数字用户 ID', 'warning')
      return
    }
  }
  if (needsTurnstile.value && !turnstileToken.value.trim() && !form.accessToken.trim()) {
    store.notify(
      turnstileBlocked.value
        ? '当前页无法完成该站点的 Cloudflare 验证，请粘贴站点登录后的 JWT，或改用 App'
        : '请先完成 Cloudflare 人机验证',
      'warning'
    )
    return
  }

  saving.value = true
  const autoLogin =
    usePasswordLogin.value &&
    !form.accessToken.trim() &&
    (!isEditing.value || Boolean(form.password) || editingExpired.value)
  if (autoLogin) {
    authOverlay.value = true
    authError.value = ''
    authStage.value = 'checking'
    authDetail.value = '读取站点公开设置'
  }
  try {
    if (autoLogin) {
      authStage.value = needsTurnstile.value ? 'captcha' : 'captcha'
      authDetail.value = needsTurnstile.value ? '使用当前页完成的人机验证' : '该站点无需人机验证'
      authStage.value = 'submitting'
      authDetail.value = '提交登录并获取凭证'
    }
    const account = await store.saveAccount({
      ...form,
      turnstileToken: turnstileToken.value.trim() || undefined
    })
    store.notify(
      editingExpired.value ? '已重新登录并同步' : isEditing.value ? '账号已重新同步' : '账号已自动登录并同步'
    )
    uni.redirectTo({ url: `/pages/accounts/detail?id=${account.id}` })
  } catch (error) {
    turnstileToken.value = ''
    turnstileReset.value += 1
    const message = error instanceof Error ? error.message : '连接失败'
    if (autoLogin) {
      authError.value = message
    }
    store.notify(message, 'error')
  } finally {
    capturing.value = false
    saving.value = false
  }
}
</script>

<template>
  <AppShell
    :title="pageTitle"
    subtitle="调用站点接口自动登录"
    show-back
    back-url="/pages/accounts/index"
  >
    <view class="yc-content account-form">
      <view v-if="isEditing" class="account-form__tip">
        <view class="account-form__tip-icon">i</view>
        <text>{{
          editingExpired
            ? '当前站点登录已过期。填写用户名和密码后会调用站点接口自动登录。'
            : '用户名密码会调用站点接口自动登录。额度、Key 和日志会从站点实时读取。'
        }}</text>
      </view>

      <view class="account-form__preview yc-card">
        <image
          class="account-form__preview-icon"
          :src="selectedPreset.iconAsset"
          mode="aspectFill"
        />
        <view>
          <text class="account-form__preview-title">{{ form.alias || form.username || '未命名账号' }}</text>
          <text class="account-form__preview-subtitle">{{ previewHost }} · {{ selectedPreset.label }}</text>
        </view>
      </view>

      <view class="yc-section-title"><text>账号类型</text></view>
      <view class="account-form__types">
        <button
          v-for="preset in platformTypeOptions"
          :key="preset.type"
          class="account-form__type-chip"
          :class="{ 'account-form__type-chip--active': form.platformType === preset.type }"
          :style="
            form.platformType === preset.type
              ? { borderColor: preset.color, background: preset.lightColor, color: preset.color }
              : undefined
          "
          @click="selectPlatform(preset.type)"
        >
          <image
            class="account-form__type-chip-mark"
            :src="preset.iconAsset"
            mode="aspectFill"
          />
          <text>{{ preset.label }}</text>
        </button>
      </view>
      <text class="account-form__type-hint">{{
        isEditing ? selectedPreset.description : '填写站点地址后会自动识别 NewAPI 或 Sub2API，也可手动点选。'
      }}</text>

      <view class="yc-section-title"><text>站点与备注</text></view>
      <view class="account-form__card yc-card">
        <view class="account-form__field">
          <text class="account-form__label">站点地址 <text class="account-form__required">*</text></text>
          <NutInput
            v-model="form.baseUrl"
            clearable
            :placeholder="isSub2Api ? 'https://www.miapi.cc' : 'https://your-newapi.example'"
          />
        </view>
        <view class="account-form__field">
          <text class="account-form__label">本地备注</text>
          <NutInput v-model="form.alias" clearable placeholder="例如：主账号、开发测试" />
        </view>
        <view class="account-form__field account-form__field--last">
          <text class="account-form__label">站点名称</text>
          <NutInput v-model="form.siteName" clearable placeholder="可留空，默认使用域名" />
          <view class="account-form__tags">
            <button
              v-for="tag in tagOptions"
              :key="tag"
              class="account-form__tag"
              :class="{ 'account-form__tag--active': form.tags.includes(tag) }"
              @click="toggleTag(tag)"
            >
              {{ tag }}
            </button>
          </view>
        </view>
      </view>

      <view class="yc-section-title"><text>登录方式</text></view>
      <view class="account-form__auth">
        <view v-if="supportsAccessToken" class="account-form__type-grid">
          <view
            class="account-form__type"
            :class="{ 'account-form__type--active': form.authMode === 'password' }"
            @click="setAuthMode('password')"
          >
            <view class="account-form__type-copy account-form__type-copy--solo">
              <text>用户名密码</text>
              <text>调用接口自动登录</text>
            </view>
          </view>
          <view
            class="account-form__type"
            :class="{ 'account-form__type--active': form.authMode === 'access_token' }"
            @click="setAuthMode('access_token')"
          >
            <view class="account-form__type-copy account-form__type-copy--solo">
              <text>访问令牌</text>
              <text>个人设置中的系统令牌</text>
            </view>
          </view>
        </view>

        <view class="account-form__card yc-card">
          <template v-if="form.authMode === 'password' || !supportsAccessToken">
            <view class="account-form__field">
              <text class="account-form__label">
                {{ selectedPreset.identityLabel }}
                <text class="account-form__required">*</text>
              </text>
              <NutInput
                v-model="form.username"
                clearable
                :placeholder="selectedPreset.identityPlaceholder"
              />
            </view>
            <view class="account-form__field account-form__field--last">
              <text class="account-form__label">密码 <text v-if="!isEditing" class="account-form__required">*</text></text>
              <NutInput v-model="form.password" type="password" placeholder="登录成功后用于再次自动登录" />
              <text class="account-form__hint">{{
                editingExpired
                  ? '登录已过期，填写密码后会自动登录。'
                  : isEditing
                    ? '留空则继续使用已保存的会话。要重新登录时再填。'
                    : '会用来调用站点接口自动登录。该站点若开启人机验证，请先在下方完成。'
              }}</text>
            </view>
            <view class="account-form__field account-form__field--last">
              <text class="account-form__hint">点「自动登录」会调用站点接口登录，不打开网站。</text>
            </view>
            <view v-if="isSub2Api && probingSite" class="account-form__field account-form__field--last">
              <text class="account-form__hint">正在读取站点验证设置…</text>
            </view>
            <view v-else-if="isSub2Api && sub2SettingsError" class="account-form__field account-form__field--last">
              <text class="account-form__hint">{{ sub2SettingsError }}。确认站点地址后会自动重试。</text>
            </view>
            <view v-else-if="needsTurnstile" class="account-form__field account-form__field--last">
              <text class="account-form__label">Cloudflare 验证 <text class="account-form__required">*</text></text>
              <TurnstileWidget
                :site-key="sub2Settings?.turnstile_site_key || ''"
                :theme="store.settings.darkMode ? 'dark' : 'light'"
                :reset-signal="turnstileReset"
                @token="turnstileToken = $event; turnstileBlocked = false"
                @expire="turnstileToken = ''"
                @error="turnstileToken = ''; turnstileBlocked = true"
              />
              <text class="account-form__hint">该站点开启了 Cloudflare Turnstile，完成验证后才能登录。</text>
            </view>
            <view v-if="isSub2Api && turnstileBlocked" class="account-form__field account-form__field--last">
              <text class="account-form__label">登录令牌</text>
              <NutInput v-model="form.accessToken" type="password" placeholder="站点登录后的 JWT，可选项" />
              <text class="account-form__hint">当前页若无法完成验证（常见于本地预览域名不匹配），可粘贴站点 Local Storage 里的 auth_token。</text>
            </view>
          </template>
          <template v-else>
            <view class="account-form__field">
              <text class="account-form__label">系统访问令牌 <text v-if="!isEditing" class="account-form__required">*</text></text>
              <NutInput v-model="form.accessToken" type="password" placeholder="个人设置 - 系统访问令牌" />
              <text class="account-form__hint">这不是 sk- 开头的模型调用 Key。</text>
            </view>
            <view class="account-form__field account-form__field--last">
              <text class="account-form__label">用户 ID <text class="account-form__required">*</text></text>
              <NutInput v-model="form.userId" clearable placeholder="个人设置里的数字 ID" />
              <text class="account-form__hint">AgentRouter 等站点必须同时携带 New-Api-User。</text>
            </view>
          </template>
        </view>
      </view>

      <NutButton
        class="account-form__save"
        block
        shape="round"
        custom-color="#fa2c19"
        :loading="saving || capturing"
        @click="save"
      >
        {{
          capturing || (saving && authOverlay && !authError)
            ? '登录中…'
            : editingExpired
              ? '自动登录'
              : isEditing
                ? '保存并同步'
                : '自动登录'
        }}
      </NutButton>
    </view>
    <view v-if="authOverlay" class="site-auth-scrim">
      <view class="site-auth-card">
        <view class="site-auth-card__title">
          <text>{{ authError ? '自动登录中断' : '自动登录进度' }}</text>
        </view>
        <view
          v-for="(step, index) in loginSteps"
          :key="step.id"
          class="site-auth-step"
        >
          <text class="site-auth-step__mark">{{
            authStepState(index) === 'done'
              ? '✓'
              : authStepState(index) === 'error'
                ? '!'
                : authStepState(index) === 'active'
                  ? '…'
                  : '○'
          }}</text>
          <view class="site-auth-step__copy">
            <text class="site-auth-step__title">{{ step.title }}</text>
            <text class="site-auth-step__sub">{{
              authStepState(index) === 'active' && authDetail ? authDetail : step.subtitle
            }}</text>
          </view>
        </view>
        <text v-if="authError" class="site-auth-card__error">{{ authError }}</text>
        <NutButton
          v-if="authError"
          class="site-auth-card__retry"
          block
          shape="round"
          custom-color="#fa2c19"
          @click="save"
        >
          重试
        </NutButton>
        <NutButton
          v-if="authError"
          class="site-auth-card__close"
          block
          plain
          shape="round"
          custom-color="#fa2c19"
          @click="dismissAuthProgress"
        >
          关闭
        </NutButton>
      </view>
    </view>
  </AppShell>
</template>

<style scoped lang="scss">
.account-form {
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

  &__preview-icon,
  &__type-icon {
    display: flex;
    align-items: center;
    justify-content: center;
    color: #fff;
    font-weight: 800;
  }

  &__preview-icon {
    width: 66rpx;
    height: 66rpx;
    flex: none;
    margin-right: 16rpx;
    border-radius: 21rpx;
    overflow: hidden;
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

  &__type-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 16rpx;
    margin-bottom: 4rpx;

    :deep(uni-button) {
      display: flex;
      width: 100%;
    }
  }

  &__types {
    display: flex;
    flex-wrap: wrap;
    gap: 12rpx;

    :deep(uni-button) {
      display: inline-flex;
      width: auto;
    }
  }

  &__type-chip {
    display: inline-flex;
    width: auto;
    max-width: 100%;
    align-items: center;
    gap: 10rpx;
    margin: 0;
    padding: 8rpx 18rpx 8rpx 8rpx;
    border: 1rpx solid var(--yc-line);
    border-radius: 999rpx;
    background: var(--yc-surface);
    color: var(--yc-ink);
    font-size: 24rpx;
    font-weight: 700;
    line-height: 1.2;
    white-space: nowrap;

    :deep(uni-text) {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }

  &__type-chip-mark {
    display: flex;
    width: 40rpx;
    height: 40rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 12rpx;
    overflow: hidden;
  }

  &__type-hint {
    display: block;
    margin: 12rpx 4rpx 8rpx;
    color: var(--yc-muted);
    font-size: 20rpx;
  }

  &__auth {
    display: flex;
    flex-direction: column;
    gap: 24rpx;
    margin-bottom: 8rpx;
  }

  &__type {
    display: flex;
    width: 100%;
    min-width: 0;
    box-sizing: border-box;
    align-items: center;
    margin: 0;
    padding: 22rpx 20rpx;
    border: 1rpx solid transparent;
    border-radius: 22rpx;
    background: var(--yc-surface);
    box-shadow: 0 10rpx 26rpx rgba(28, 32, 39, 0.04);
    text-align: left;

    &--active {
      border-color: rgba(250, 44, 25, 0.2);
      box-shadow: 0 12rpx 28rpx rgba(250, 44, 25, 0.1);
    }
  }

  &__type-icon {
    width: 48rpx;
    height: 48rpx;
    flex: none;
    border-radius: 16rpx;
    font-size: 22rpx;
  }

  &__type-copy {
    display: flex;
    min-width: 0;
    flex-direction: column;
    margin-left: 12rpx;

    &--solo {
      margin-left: 0;
    }

    text:first-child {
      color: var(--yc-ink);
      font-size: 23rpx;
      font-weight: 750;
    }

    text:last-child {
      overflow: hidden;
      margin-top: 4rpx;
      color: var(--yc-muted);
      text-overflow: ellipsis;
      white-space: nowrap;
      font-size: 17rpx;
    }
  }

  &__card {
    overflow: hidden;
    padding: 4rpx 24rpx;
  }

  &__field {
    min-width: 0;
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

    :deep(.nut-input__value),
    :deep(.uni-input-wrapper) {
      display: flex;
      min-width: 0;
      width: 100%;
      align-items: center;
    }

    :deep(.uni-input-input),
    :deep(.input-placeholder) {
      color: var(--yc-ink);
      font-size: 23rpx;
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

  &__two-fields {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 20rpx;
    border-top: 1rpx solid var(--yc-line);
  }

  &__label {
    display: block;
    color: var(--yc-ink);
    font-size: 23rpx;
    font-weight: 650;
  }

  &__required {
    color: $yc-primary;
  }

  &__hint {
    display: block;
    margin-top: 7rpx;
    color: var(--yc-muted);
    font-size: 19rpx;
    line-height: 1.45;
  }

  &__tags,
  &__groups {
    display: flex;
    flex-wrap: wrap;
    gap: 12rpx;
    margin-top: 14rpx;
  }

  &__tag,
  &__group {
    display: inline-flex;
    height: 54rpx;
    align-items: center;
    justify-content: center;
    margin: 0;
    padding: 0 20rpx;
    border: 1rpx solid var(--yc-line);
    border-radius: 999rpx;
    background: transparent;
    color: var(--yc-muted);
    font-size: 20rpx;
    font-weight: 700;
    line-height: 1;
  }

  &__tag--active,
  &__group--active {
    border-color: rgba(250, 44, 25, 0.22);
    background: #fff0ed;
    color: $yc-primary;
  }

  &__save {
    margin-top: 48rpx;
    margin-bottom: 24rpx;

    :deep(.nut-button) {
      height: 84rpx;
      font-size: 27rpx;
      font-weight: 750;
    }
  }
}

.site-auth-scrim {
  position: fixed;
  inset: 0;
  z-index: 1200;
  display: flex;
  align-items: center;
  justify-content: center;
  padding: 48rpx;
  background: rgba(0, 0, 0, 0.28);
  backdrop-filter: blur(18px);
}

.site-auth-card {
  width: 100%;
  max-width: 640rpx;
  padding: 32rpx;
  border-radius: 36rpx;
  border: 1rpx solid rgba(255, 255, 255, 0.28);
  background: color-mix(in srgb, var(--yc-surface) 84%, transparent);
  backdrop-filter: blur(22px);
  box-shadow: 0 24rpx 80rpx rgba(0, 0, 0, 0.18);

  &__title {
    margin-bottom: 18rpx;
    color: var(--yc-ink);
    font-size: 30rpx;
    font-weight: 800;
  }

  &__error {
    display: block;
    margin-top: 16rpx;
    padding: 16rpx;
    border-radius: 16rpx;
    background: rgba(190, 38, 48, 0.08);
    color: #be2630;
    font-size: 22rpx;
    line-height: 1.45;
  }

  &__retry {
    margin-top: 24rpx;
  }

  &__close {
    margin-top: 12rpx;
  }
}

.site-auth-step {
  display: flex;
  gap: 16rpx;
  padding: 10rpx 0;

  &__mark {
    width: 36rpx;
    color: var(--yc-muted);
    font-size: 24rpx;
    font-weight: 800;
    line-height: 1.4;
    text-align: center;
  }

  &__copy {
    flex: 1;
    min-width: 0;
  }

  &__title {
    display: block;
    color: var(--yc-ink);
    font-size: 26rpx;
    font-weight: 700;
  }

  &__sub {
    display: block;
    margin-top: 4rpx;
    color: var(--yc-muted);
    font-size: 22rpx;
    line-height: 1.4;
  }
}

</style>
