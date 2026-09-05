<script setup lang="ts">
import { computed } from 'vue'

const props = withDefaults(
  defineProps<{
    size?: number
    showWordmark?: boolean
    inverse?: boolean
    compact?: boolean
  }>(),
  {
    size: 72,
    showWordmark: false,
    inverse: false,
    compact: false
  }
)

const source = computed(() => {
  if (!props.showWordmark) {
    return '/static/brand/yucon-app-icon.png'
  }
  return props.inverse
    ? '/static/brand/yucon-lockup-dark.png'
    : '/static/brand/yucon-lockup-light.png'
})

const imageStyle = computed(() => {
  const height = props.showWordmark && props.compact
    ? Math.round(props.size * 0.9)
    : props.size
  const ratio = props.showWordmark ? 3.78 : 1
  return {
    width: `${Math.round(height * ratio)}rpx`,
    height: `${height}rpx`
  }
})
</script>

<template>
  <view
    class="brand-mark"
    :class="{
      'brand-mark--inverse': inverse,
      'brand-mark--compact': compact
    }"
  >
    <image class="brand-mark__asset" :src="source" :style="imageStyle" mode="aspectFit" />
  </view>
</template>

<style scoped lang="scss">
.brand-mark {
  display: inline-flex;
  align-items: center;
  min-width: 0;

  &__asset {
    display: block;
    flex: none;
  }
}
</style>
