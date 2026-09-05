<script setup lang="ts">
import { computed, onUnmounted, ref, watch } from 'vue'
import ModelBrandIcon from '@/components/ModelBrandIcon.vue'
import { NutPopup, NutSearchbar } from '@/components/nutui'
import type { ModelVendorKey } from '@/constants/model-brands'
import { lockPageScroll, unlockPageScroll } from '@/utils/page-scroll-lock'

export interface SelectSheetOption {
  value: string
  title: string
  subtitle?: string
  meta?: string
  icon?: ModelVendorKey
}

const props = defineProps<{
  visible: boolean
  title: string
  options: SelectSheetOption[]
  modelValue?: string
  multiple?: boolean
  searchable?: boolean
  showIcons?: boolean
  selectedValues?: string[]
}>()

const emit = defineEmits<{
  'update:visible': [boolean]
  change: [string]
  confirm: [string[]]
}>()

const keyword = ref('')
const selectedSet = computed(() => new Set(props.selectedValues ?? []))
const filteredOptions = computed(() => {
  const query = keyword.value.trim().toLowerCase()
  if (!query) {
    return props.options
  }
  return props.options.filter(
    (option) =>
      option.title.toLowerCase().includes(query) ||
      option.subtitle?.toLowerCase().includes(query) ||
      option.value.toLowerCase().includes(query)
  )
})

watch(
  () => props.visible,
  (visible) => {
    if (visible) {
      lockPageScroll()
      return
    }
    keyword.value = ''
    unlockPageScroll()
  }
)

onUnmounted(() => {
  if (props.visible) {
    unlockPageScroll()
  }
})

const isSelected = (value: string): boolean =>
  props.multiple ? selectedSet.value.has(value) : value === props.modelValue

const close = (): void => {
  emit('update:visible', false)
}

const selectOne = (value: string): void => {
  emit('change', value)
  close()
}

const toggleMany = (value: string): void => {
  const next = new Set(selectedSet.value)
  if (next.has(value)) {
    next.delete(value)
  } else {
    next.add(value)
  }
  emit('confirm', [...next])
}
</script>

<template>
  <NutPopup
    :visible="visible"
    pop-class="yc-select-popup"
    overlay-class="yc-select-overlay"
    position="bottom"
    round
    lock-scroll
    safe-area-inset-bottom
    @click-overlay="close"
  >
    <view class="select-sheet">
      <view class="select-sheet__head">
        <text class="select-sheet__title">{{ title }}</text>
        <view class="select-sheet__close" role="button" @click.stop="close">
          <text>×</text>
        </view>
      </view>
      <NutSearchbar
        v-if="searchable"
        v-model="keyword"
        class="select-sheet__search"
        placeholder="搜索"
      />
      <view class="select-sheet__list yc-scroll-allow">
        <view
          v-for="option in filteredOptions"
          :key="option.value"
          class="select-sheet__option"
          :class="{ 'select-sheet__option--active': isSelected(option.value) }"
          @click="multiple ? toggleMany(option.value) : selectOne(option.value)"
        >
          <ModelBrandIcon
            v-if="showIcons"
            :model="option.value"
            :vendor="option.icon"
            size="md"
          />
          <view class="select-sheet__copy">
            <text class="select-sheet__name">{{ option.title }}</text>
            <text v-if="option.subtitle" class="select-sheet__desc">{{ option.subtitle }}</text>
          </view>
          <text v-if="option.meta" class="select-sheet__meta">{{ option.meta }}</text>
          <view v-if="isSelected(option.value)" class="select-sheet__check" aria-hidden="true">
            <svg viewBox="0 0 24 24">
              <path d="M5.2 12.6 9.7 17.2 18.8 7.4" />
            </svg>
          </view>
        </view>
      </view>
    </view>
  </NutPopup>
</template>

<style scoped lang="scss">
.select-sheet {
  display: flex;
  max-height: 72vh;
  flex-direction: column;
  overflow: hidden;
  padding: 12rpx 8rpx calc(24rpx + env(safe-area-inset-bottom));
  background: var(--yc-surface);

  &__head {
    display: flex;
    flex: none;
    align-items: center;
    justify-content: space-between;
    gap: 16rpx;
    padding: 20rpx 12rpx 12rpx 20rpx;
  }

  &__title {
    min-width: 0;
    flex: 1;
    color: var(--yc-ink);
    font-size: 32rpx;
    font-weight: 800;
  }

  &__close {
    display: flex;
    width: 56rpx;
    height: 56rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    border-radius: 99rpx;
    color: var(--yc-muted);
    font-size: 44rpx;
    line-height: 1;
  }

  &__search {
    flex: none;
    margin: 0 16rpx 8rpx;
  }

  &__list {
    min-height: 0;
    max-height: 52vh;
    overflow-x: hidden;
    overflow-y: auto;
    overscroll-behavior: contain;
    -webkit-overflow-scrolling: touch;
  }

  &__option {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16rpx;
    margin: 0 16rpx;
    padding: 16rpx 18rpx;
    border-radius: 18rpx;

    &--active {
      background: #fff0ed;
    }
  }

  &__copy {
    min-width: 0;
    flex: 1;
  }

  &__name,
  &__desc,
  &__meta {
    display: block;
  }

  &__name {
    color: var(--yc-ink);
    font-size: 26rpx;
    font-weight: 700;
  }

  &__desc {
    margin-top: 4rpx;
    overflow: hidden;
    color: var(--yc-muted);
    text-overflow: ellipsis;
    white-space: nowrap;
    font-size: 20rpx;
  }

  &__meta {
    flex: none;
    color: $yc-primary;
    font-size: 24rpx;
    font-weight: 750;
  }

  &__check {
    display: flex;
    width: 36rpx;
    height: 36rpx;
    flex: none;
    align-items: center;
    justify-content: center;
    color: $yc-primary;

    svg {
      display: block;
      width: 32rpx;
      height: 32rpx;
      fill: none;
      stroke: currentColor;
      stroke-linecap: round;
      stroke-linejoin: round;
      stroke-width: 2.6;
    }
  }
}
</style>
