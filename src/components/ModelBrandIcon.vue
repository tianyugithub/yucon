<script setup lang="ts">
import { computed } from 'vue'
import {
  brandFromKey,
  detectModelBrand,
  modelBrandIconSrc,
  type ModelVendorKey
} from '@/constants/model-brands'

const props = withDefaults(
  defineProps<{
    model?: string
    vendor?: ModelVendorKey
    size?: 'sm' | 'md'
  }>(),
  {
    model: '',
    size: 'md'
  }
)

const brand = computed(() =>
  props.vendor && props.vendor !== 'unknown'
    ? brandFromKey(props.vendor)
    : detectModelBrand(props.model)
)
const iconSrc = computed(() => modelBrandIconSrc(brand.value.key))
const initial = computed(() => (brand.value.label.slice(0, 1) || '?').toUpperCase())
const boxSize = computed(() => (props.size === 'sm' ? '28rpx' : '36rpx'))
const imageStyle = computed(() => ({
  width: boxSize.value,
  height: boxSize.value
}))
</script>

<template>
  <view
    class="model-brand-icon"
    :class="[`model-brand-icon--${size}`, { 'model-brand-icon--fallback': !iconSrc }]"
    :aria-label="brand.label"
  >
    <image
      v-if="iconSrc"
      class="model-brand-icon__mark"
      :src="iconSrc"
      :style="imageStyle"
      mode="aspectFit"
    />
    <text v-else class="model-brand-icon__initial">{{ initial }}</text>
  </view>
</template>

<style scoped lang="scss">
.model-brand-icon {
  display: flex;
  flex: none;
  align-items: center;
  justify-content: center;
  overflow: hidden;
  border-radius: 12rpx;
  background: #f4f5f7;

  &--sm {
    width: 28rpx;
    height: 28rpx;
    border-radius: 8rpx;
  }

  &--md {
    width: 36rpx;
    height: 36rpx;
    border-radius: 10rpx;
  }

  &--fallback {
    background: #69707c;
  }

  &__mark {
    display: block;
    width: 100%;
    height: 100%;

    :deep(img),
    :deep(div) {
      width: 100% !important;
      height: 100% !important;
    }
  }

  &__initial {
    color: #fff;
    font-size: 16rpx;
    font-weight: 800;
    line-height: 1;
  }
}
</style>
