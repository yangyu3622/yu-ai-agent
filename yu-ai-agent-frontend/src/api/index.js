import axios from 'axios'

// 【2026 改动】原版用的 process.env.NODE_ENV 在 Vite 里是未定义的，浏览器会抛
// "process is not defined"。Vite 正确读法是 import.meta.env。
// 优先级：显式环境变量 VITE_API_BASE_URL > 生产默认同源 /api > 开发默认 8123
const API_BASE_URL =
  import.meta.env.VITE_API_BASE_URL ||
  (import.meta.env.PROD ? '/api' : 'http://localhost:8123/api')

// 创建 axios 实例
const request = axios.create({
  baseURL: API_BASE_URL,
  timeout: 60000
})

// 封装 SSE 连接
export const connectSSE = (url, params, onMessage, onError) => {
  // 构建带参数的 URL
  const queryString = Object.keys(params)
    .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(params[key])}`)
    .join('&')

  const fullUrl = `${API_BASE_URL}${url}?${queryString}`

  // 创建 EventSource（SSE 不支持自定义 header，参数只能走 query）
  const eventSource = new EventSource(fullUrl)

  eventSource.onmessage = event => {
    let data = event.data

    // 检查是否是特殊标记
    if (data === '[DONE]') {
      if (onMessage) onMessage('[DONE]')
    } else {
      // 处理普通消息
      if (onMessage) onMessage(data)
    }
  }

  eventSource.onerror = error => {
    if (onError) onError(error)
    eventSource.close()
  }

  // 返回 eventSource 实例，以便后续可以关闭连接
  return eventSource
}

// AI 恋爱大师聊天
export const chatWithLoveApp = (message, chatId) => {
  return connectSSE('/ai/love_app/chat/sse', { message, chatId })
}

// AI 超级智能体聊天
export const chatWithManus = (message) => {
  return connectSSE('/ai/manus/chat', { message })
}

export default {
  request,
  chatWithLoveApp,
  chatWithManus
}
