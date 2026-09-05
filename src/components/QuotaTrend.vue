<script setup lang="ts">
import { computed } from 'vue'
import { formatCurrency } from '@/utils/format'
import type { BalancePoint } from '@/types/domain'

const props = defineProps<{
  points: BalancePoint[]
}>()

const chartWidth = 600
const chartHeight = 170
const top = 12
const bottom = 38
const left = 10
const right = 10

const range = computed(() => {
  const values = props.points.map((point) => point.value)
  const min = Math.min(...values, 0)
  const max = Math.max(...values, 1)
  const padding = Math.max((max - min) * 0.2, 1)
  return { min: Math.max(0, min - padding), max: max + padding }
})

const coordinates = computed(() => {
  const drawableWidth = chartWidth - left - right
  const drawableHeight = chartHeight - top - bottom
  const denominator = Math.max(range.value.max - range.value.min, 1)
  return props.points.map((point, index) => {
    const x =
      props.points.length > 1
        ? left + (drawableWidth * index) / (props.points.length - 1)
        : chartWidth / 2
    const y = top + ((range.value.max - point.value) / denominator) * drawableHeight
    return { ...point, x, y }
  })
})

const linePoints = computed(() =>
  coordinates.value.map((point) => `${point.x},${point.y}`).join(' ')
)

const areaPoints = computed(() => {
  if (!coordinates.value.length) {
    return ''
  }
  const first = coordinates.value[0]
  const last = coordinates.value[coordinates.value.length - 1]
  return `${first.x},${chartHeight - bottom} ${linePoints.value} ${last.x},${chartHeight - bottom}`
})

const latest = computed(() => props.points[props.points.length - 1]?.value ?? 0)
</script>

<template>
  <view class="quota-trend">
    <view class="quota-trend__head">
      <view>
        <text class="quota-trend__title">7 日额度趋势</text>
        <text class="quota-trend__subtitle">按最近同步记录</text>
      </view>
      <text class="quota-trend__latest">{{ formatCurrency(latest) }}</text>
    </view>

    <view v-if="coordinates.length" class="quota-trend__chart">
      <svg viewBox="0 0 600 170" preserveAspectRatio="none" aria-hidden="true">
        <defs>
          <linearGradient id="quota-area" x1="0" x2="0" y1="0" y2="1">
            <stop offset="0%" stop-color="#fa2c19" stop-opacity="0.22" />
            <stop offset="100%" stop-color="#fa2c19" stop-opacity="0.01" />
          </linearGradient>
        </defs>
        <path
          d="M10 132H590"
          stroke="rgba(125, 132, 144, 0.18)"
          stroke-dasharray="6 8"
          stroke-width="1"
        />
        <polygon :points="areaPoints" fill="url(#quota-area)" />
        <polyline
          :points="linePoints"
          fill="none"
          stroke="#fa2c19"
          stroke-linecap="round"
          stroke-linejoin="round"
          stroke-width="4"
        />
        <circle
          v-for="(point, index) in coordinates"
          :key="`${point.label}-${index}`"
          :cx="point.x"
          :cy="point.y"
          r="4.5"
          fill="#fff"
          stroke="#fa2c19"
          stroke-width="3"
        />
      </svg>
      <view class="quota-trend__labels">
        <text v-for="(point, index) in coordinates" :key="`${point.label}-${index}`">{{ point.label }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.quota-trend {
  &__head {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
  }

  &__title,
  &__subtitle,
  &__latest {
    display: block;
  }

  &__title {
    color: var(--yc-ink);
    font-size: 26rpx;
    font-weight: 750;
  }

  &__subtitle {
    margin-top: 5rpx;
    color: var(--yc-muted);
    font-size: 19rpx;
  }

  &__latest {
    color: $yc-primary;
    font-size: 27rpx;
    font-weight: 800;
  }

  &__chart {
    margin-top: 20rpx;
  }

  svg {
    display: block;
    width: 100%;
    height: 170rpx;
  }

  &__labels {
    display: flex;
    justify-content: space-between;
    margin-top: 2rpx;
    color: var(--yc-muted);
    font-size: 18rpx;
  }
}
</style>
