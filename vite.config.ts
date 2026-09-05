import { defineConfig } from 'vite'
import uni from '@dcloudio/vite-plugin-uni'
import { fileURLToPath, URL } from 'node:url'
import { yuconProxyPlugin } from './yucon-proxy'

export default defineConfig({
  base: process.env.YUCON_NATIVE === '1' ? './' : undefined,
  plugins: [uni(), yuconProxyPlugin()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  css: {
    preprocessorOptions: {
      scss: {
        additionalData:
          '@import "nutui-uniapp/styles/variables.scss";\n@import "@/styles/tokens.scss";'
      }
    }
  }
})
