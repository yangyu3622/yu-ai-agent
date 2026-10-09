# AI 超级智能体

> 基于 **Spring Boot 3.5.16 + Spring AI 1.1.8 + Spring AI Alibaba 1.1.2.2** 的企业级 AI 智能体全栈项目。
> 原型来自编程导航《AI 超级智能体》，本仓库已把 2025 年的旧依赖整体迁移到 **2026-10 可用**的版本矩阵，并补齐 CI / 容器化 / 服务器部署链路。

- 后端：`http://服务器IP/api/doc.html`（Knife4j 接口文档）
- 前端：`http://服务器IP`

---

## 一、技术栈（2026-10 版本矩阵）

| 组件 | 原版（已过时） | 本仓库 | 说明 |
| --- | --- | --- | --- |
| JDK | 21 | 21 | 不变 |
| Spring Boot | 3.4.4 | **3.5.16** | 3.5.x 线最后一个 OSS 版本 |
| Spring AI | 1.0.0 | **1.1.8** | 1.1.x 线最新维护版 |
| Spring AI Alibaba | 1.0.0.2 | **1.1.2.2** | 对齐 Spring AI 1.1.2 / Boot 3.5.x |
| DashScope Starter | 由 SAA BOM 管理 | **1.1.2.2（显式）** | SAA 1.1.x 起 BOM 漏管，必须写版本 |
| 向量库 | PgVector | PgVector（可切换内存库） | 默认走 SimpleVectorStore，零依赖 |
| 前端 | Vue3 + Vite 4 | **Vue3.5 + Vite 6** | 修掉 `process is not defined` |
| 部署 | 单阶段 Dockerfile | **多阶段构建 + Nginx 反代** | 镜像体积降至 1/3 |

## 二、核心能力

- **多轮对话记忆**：`MessageWindowChatMemory` + 文件持久化（Kryo 序列化）
- **RAG 知识库**：Markdown ETL → 关键词元信息增强 → 向量检索 → 查询重写
- **结构化输出**：恋爱报告实体自动映射
- **Tool Calling**：文件读写 / 联网搜索 / 网页抓取 / 资源下载 / PDF 生成 / 终端操作（6 种工具）
- **MCP**：图片搜索 MCP 服务，支持 Stdio + SSE 双传输
- **自主规划智能体 YuManus**：ReAct 模式，自主拆解任务并调用工具
- **SSE 流式输出**：实时输出智能体思考与执行过程

## 三、本次迁移修复的过时点（面试可讲）

1. **`spring.ai.model.chat=dashscope` 必须显式声明**
   SAA 1.1.x 起自动配置类带了 `@ConditionalOnProperty`，不写这行 `DashScopeChatModel` 的 Bean 根本不创建，启动即报 `No qualifying bean of type ChatModel`。这是从 1.0 升到 1.1 **最容易踩的坑**。

2. **`QuestionAnswerAdvisor` 构造器变包级私有**
   `new QuestionAnswerAdvisor(vectorStore)` 无法编译 → 改为 `QuestionAnswerAdvisor.builder(vectorStore).build()`。

3. **`TokenTextSplitter` 5 参构造器被移除**
   `new TokenTextSplitter(200, 100, 10, 5000, true)` 无法编译 → 改为 Builder 链。

4. **ChatModel Bean 名从 `dashscopeChatModel` 变成 `dashScopeChatModel`**（大写 S）
   所有注入点补 `@Qualifier("dashScopeChatModel")`，避免与 Ollama 的 ChatModel 撞车。

5. **新建 `DashScopeChatOptions` 会覆盖 yml 配置**
   `ModelOptionsUtils.merge` 规则是「runtime 非空覆盖 default」，只设 `internalToolExecutionEnabled` 的新对象会把 `multiModel` 等默认值一起盖掉。改为从 `chatModel.getDefaultOptions()` 取基底再改单字段。

6. **`TerminalOperationTool` 硬编码 `cmd.exe`** → 按 OS 自动选择 shell 并加 60s 超时，否则 AI 触发 `tail -f` 会永久阻塞。

7. **前端 `process.env.NODE_ENV`** 在 Vite 中未定义（浏览器报 `process is not defined`）→ 改用 `import.meta.env`。

8. **nginx 反代写死 `www.codefather.cn`** → 改为本机 `http://127.0.0.1:8123`。

9. **`spring-ai-alibaba-starter-dashscope` 需引入 `spring-ai-alibaba-extensions-bom`**
   SAA 1.1.x 把 DashScope 模型适配拆到了独立仓库 `spring-ai-alibaba/spring-ai-extensions`。

## 四、本地启动

```bash
# 1. 准备环境变量（Windows 用户用系统环境变量或 IDEA 启动参数）
export AI_DASHSCOPE_API_KEY=sk-你的百炼Key
export SEARCH_API_KEY=你的searchapiKey   # 联网搜索工具，可选

# 2. 启动后端（首次会下载依赖，约 3-5 分钟）
./mvnw spring-boot:run

# 3. 启动前端
cd yu-ai-agent-frontend
npm install && npm run dev
```

验证接口（另开一个终端）：

```bash
curl "http://localhost:8123/api/ai/love_app/chat/sync?message=你好&chatId=test1"
curl "http://localhost:8123/api/health"
```

## 五、部署到阿里云轻量服务器

详细图文步骤见 **[DEPLOY.md](./DEPLOY.md)**，精简版：

```bash
# 服务器上执行一次
curl -fsSL https://get.docker.com | bash
git clone https://github.com/你的用户名/yu-ai-agent.git /root/yu-ai-agent
cd /root/yu-ai-agent && chmod +x deploy.sh && ./deploy.sh init
vim .env      # 填入真实的 AI_DASHSCOPE_API_KEY / SEARCH_API_KEY
./deploy.sh   # 构建 + 启动 + 健康检查
```

后续更新代码只需在服务器执行 `./deploy.sh`。

> 轻量服务器建议 **2 核 2G 及以上**（1G 内存跑 Docker 构建会 OOM）。若只有 1G，改用「本地打包 jar → scp 上传 → java -jar」的方式，见 DEPLOY.md 方案 B。

## 六、目录结构

```
yu-ai-agent/
├── src/main/java/com/yupi/yuaiagent/
│   ├── agent/          # ReAct 自主规划智能体（BaseAgent / ReActAgent / ToolCallAgent / YuManus）
│   ├── app/            # AI 恋爱大师应用
│   ├── rag/            # RAG 知识库（文档加载 / 切分 / 向量存储 / 查询重写）
│   ├── tools/          # 6 种工具调用
│   ├── advisor/        # 自定义 Advisor（日志 / Re2 推理增强）
│   ├── chatmemory/     # 文件持久化对话记忆
│   └── controller/     # SSE 流式接口
├── yu-ai-agent-frontend/     # Vue3 前端
├── yu-image-search-mcp-server/  # 图片搜索 MCP 服务
├── docker-compose.yml        # 前后端编排
├── deploy.sh                 # 服务器一键部署
└── .github/workflows/ci.yml  # CI：后端 + MCP + 前端三重构建校验
```

## 七、致谢

项目原型来自 [程序员鱼皮](https://github.com/liyupi/yu-ai-agent) 的《AI 超级智能体》教程，本仓库在其基础上做了 2026 年的依赖升级与工程化改造。
