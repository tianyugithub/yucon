<script setup lang="ts">
type TabIconName = 'dashboard' | 'accounts' | 'keys' | 'logs' | 'profile'

defineProps<{
  name: TabIconName
}>()
</script>

<template>
  <svg
    class="tab-icon"
    viewBox="0 0 24 24"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    aria-hidden="true"
  >
    <template v-if="name === 'dashboard'">
      <rect x="3.25" y="3.25" width="17.5" height="17.5" rx="3" />
      <path d="M3.5 9.25H20.5M9.25 20.5V9.5" />
    </template>

    <template v-else-if="name === 'accounts'">
      <rect x="3" y="4.5" width="18" height="15" rx="2.75" />
      <circle cx="8.25" cy="11.5" r="2" />
      <path d="M12.5 9.25H17.5M12.5 13H17.5M6 16.25C6.6 14.95 7.35 14.3 8.25 14.3C9.15 14.3 9.9 14.95 10.5 16.25" />
    </template>

    <template v-else-if="name === 'keys'">
      <circle cx="8.5" cy="12" r="3.75" />
      <path d="M11.15 14.65L20.25 5.55M16.5 9.3L18.75 11.55M14.25 11.55L16.5 13.8" />
    </template>

    <template v-else-if="name === 'logs'">
      <path d="M4.5 7.25V4.5M4.5 4.5H7.25" />
      <path d="M4.85 4.9A8.5 8.5 0 1 1 3.5 12" />
      <path d="M12 7.5V12L15.25 14" />
    </template>

    <template v-else>
      <circle cx="12" cy="8" r="3.25" />
      <path d="M5 20.5C5.6 16.95 8.05 15 12 15C15.95 15 18.4 16.95 19 20.5" />
    </template>
  </svg>
</template>

<style scoped lang="scss">
.tab-icon {
  display: block;
  overflow: visible;
  stroke: currentColor;
  stroke-linecap: round;
  stroke-linejoin: round;
  stroke-width: 1.9;
}
</style>
