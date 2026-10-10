<template>
  <div class="super-agent-container">
    <div class="header">
      <div class="back-button" @click="goBack">返回</div>
      <h1 class="title">AI超级智能体</h1>
      <div class="placeholder"></div>
    </div>
    
    <div class="content-wrapper">
      <div class="chat-area">
        <div v-if="stepsLog.length" class="steps-panel">
          <div class="steps-toggle" @click="showSteps = !showSteps">
            {{ showSteps ? '收起' : '展开' }}思考过程（{{ stepsLog.length }} 步）
          </div>
          <div v-show="showSteps" class="steps-body">
            <div v-for="(s, i) in stepsLog" :key="i" class="step-item">{{ s }}</div>
          </div>
        </div>
        <ChatRoom 
          :messages="messages" 
          :connection-status="connectionStatus"
          ai-type="super"
          @send-message="sendMessage"
        />
      </div>
    </div>
    
    <div class="footer-container">
      <AppFooter />
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { useHead } from '@vueuse/head'
import ChatRoom from '../components/ChatRoom.vue'
import AppFooter from '../components/AppFooter.vue'
import { chatWithManus } from '../api'

useHead({
  title: 'AI超级智能体 - 瑾瑜AI超级智能体应用平台',
  meta: [
    {
      name: 'description',
      content: 'AI超级智能体是瑾瑜AI超级智能体应用平台的全能助手，能解答各类问题，提供专业建议和解决方案'
    },
    {
      name: 'keywords',
      content: 'AI超级智能体,智能助手,专业问答,AI问答,专业建议,瑾瑜,AI智能体'
    }
  ]
})

const router = useRouter()
const messages = ref([])
const connectionStatus = ref('disconnected')
const stepsLog = ref([])
const showSteps = ref(false)
let eventSource = null

const addMessage = (content, isUser, type = '') => {
  messages.value.push({
    content,
    isUser,
    type,
    time: new Date().getTime()
  })
}

const sendMessage = (message) => {
  addMessage(message, true, 'user-question')
  if (eventSource) {
    eventSource.close()
  }
  connectionStatus.value = 'connecting'
  stepsLog.value = []

  let messageBuffer = [];
  let lastBubbleTime = Date.now();
  let isFirstResponse = true;
  let finished = false;

  const chineseEndPunctuation = ['。', '！', '？', '…'];
  const minBubbleInterval = 800;

  const createBubble = (content, type = 'ai-answer') => {
    if (!content.trim()) return;
    const now = Date.now();
    const timeSinceLastBubble = now - lastBubbleTime;
    if (isFirstResponse) {
      addMessage(content, false, type);
      isFirstResponse = false;
    } else if (timeSinceLastBubble < minBubbleInterval) {
      setTimeout(() => {
        addMessage(content, false, type);
      }, minBubbleInterval - timeSinceLastBubble);
    } else {
      addMessage(content, false, type);
    }
    lastBubbleTime = now;
    messageBuffer = [];
  };

  const finishUp = () => {
    if (messageBuffer.length > 0) {
      createBubble(messageBuffer.join(''), 'ai-final');
    }
    const pdfMatch = stepsLog.value.join('\n').match(/([^\/\\]+\.pdf)/);
    if (pdfMatch) {
      addMessage('__PDF__' + pdfMatch[1], false, 'ai-pdf');
    }
    connectionStatus.value = 'disconnected';
  };

  eventSource = chatWithManus(message)

  eventSource.onmessage = (event) => {
    const data = event.data
    if (data === '[DONE]') {
      finished = true
      finishUp()
      eventSource.close()
      eventSource = null
      return
    }
    if (/^Step\s*\d+[:：]\s*(工具|思考完成|执行结束|Terminated)/.test(data)) {
      stepsLog.value.push(data)
      return
    }
    if (data) {
      messageBuffer.push(data);
      const combinedText = messageBuffer.join('');
      const lastChar = data.charAt(data.length - 1);
      const hasCompleteSentence = chineseEndPunctuation.includes(lastChar) || data.includes('\n\n');
      const isLongEnough = combinedText.length > 40;
      if (hasCompleteSentence || isLongEnough) {
        createBubble(combinedText);
      }
    }
  }

  eventSource.onerror = (error) => {
    if (finished) return
    console.error('SSE Error:', error)
    connectionStatus.value = 'error'
    const es = eventSource
    eventSource = null
    es.close()
    if (messageBuffer.length > 0) {
      createBubble(messageBuffer.join(''), 'ai-error');
    }
  }
}

const goBack = () => {
  router.push('/')
}

onMounted(() => {
  addMessage('你好，我是AI超级智能体。我可以解答各类问题，提供专业建议，请问有什么可以帮助你的吗？', false)
})

onBeforeUnmount(() => {
  if (eventSource) {
    eventSource.close()
  }
})
</script>

<style scoped>
.super-agent-container {
  display: flex;
  flex-direction: column;
  min-height: 100vh;
  background-color: #f9fbff;
}

.header {
  display: grid;
  grid-template-columns: 1fr auto 1fr;
  align-items: center;
  padding: 16px 24px;
  background-color: #3f51b5;
  color: white;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  position: sticky;
  top: 0;
  z-index: 10;
}

.back-button {
  font-size: 16px;
  cursor: pointer;
  display: flex;
  align-items: center;
  transition: opacity 0.2s;
  justify-self: start;
}

.back-button:hover {
  opacity: 0.8;
}

.back-button:before {
  content: '←';
  margin-right: 8px;
}

.title {
  font-size: 20px;
  font-weight: bold;
  margin: 0;
  text-align: center;
  justify-self: center;
}

.placeholder {
  width: 1px;
  justify-self: end;
}

.content-wrapper {
  display: flex;
  flex-direction: column;
  flex: 1;
}

.chat-area {
  flex: 1;
  padding: 16px;
  overflow: hidden;
  position: relative;
  /* 设置最小高度确保内容显示正常 */
  min-height: calc(100vh - 56px - 180px); /* 100vh减去头部高度和页脚高度 */
  margin-bottom: 16px; /* 为页脚留出空间 */
}

.steps-panel { margin: 0 0 8px 0; font-size: 13px; }
.steps-toggle { color: #3f51b5; cursor: pointer; user-select: none; display: inline-block; }
.steps-body {
  margin-top: 6px;
  padding: 8px;
  background: #f5f7ff;
  border-radius: 6px;
  max-height: 220px;
  overflow-y: auto;
}
.step-item { color: #777; margin-bottom: 4px; word-break: break-all; }

.footer-container {
  margin-top: auto;
}

/* 响应式样式 */
@media (max-width: 768px) {
  .header {
    padding: 12px 16px;
  }
  
  .title {
    font-size: 18px;
  }
  
  .chat-area {
    padding: 12px;
    min-height: calc(100vh - 48px - 160px); /* 调整计算值 */
    margin-bottom: 12px;
  }
}

@media (max-width: 480px) {
  .header {
    padding: 10px 12px;
  }
  
  .back-button {
    font-size: 14px;
  }
  
  .title {
    font-size: 16px;
  }
  
  .chat-area {
    padding: 8px;
    min-height: calc(100vh - 42px - 150px); /* 再次调整计算值 */
    margin-bottom: 8px;
  }
}

.steps-panel { margin: 8px 16px; font-size: 13px; }
.steps-toggle { color: #3f51b5; cursor: pointer; user-select: none; }
.steps-body { margin-top: 6px; padding: 8px; background: #f5f7ff; border-radius: 6px; max-height: 220px; overflow-y: auto; }
.step-item { color: #777; margin-bottom: 4px; word-break: break-all; }
</style> 