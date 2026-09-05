<script setup lang="ts">
import { onLaunch } from '@dcloudio/uni-app'
import { usePrototypeStore } from '@/stores/usePrototypeStore'
import { bindNativeChrome } from '@/utils/native-chrome'

const store = usePrototypeStore()

onLaunch(() => {
  bindNativeChrome()
  store.hydrate()
  void bootstrapVault()
})

const bootstrapVault = async (): Promise<void> => {
  if (!store.accounts.length) {
    return
  }
  await store.refreshAllAccounts()
  const results = await store.autoCheckinAccounts()
  const done = results.filter((result) => result.success).length
  if (done) {
    store.notify(`已自动完成 ${done} 个账号签到`)
  }
}
</script>

<style lang="scss">
@import './styles/global.scss';
</style>
