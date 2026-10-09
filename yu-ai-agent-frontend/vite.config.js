import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  server: {
    port: 3000,
    cors: true,
    // 开发环境直接反代后端，前端代码里就不用写死 localhost:8123 了
    proxy: {
      '/api': {
        target: 'http://localhost:8123',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    // 关掉过大的构建告警噪音
    chunkSizeWarningLimit: 1500,
    // 让产物能直接被 nginx 以 / 根路径托管
    base: './'
  }
})
