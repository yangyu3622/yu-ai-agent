# 部署上线手册（GitHub + 阿里云轻量服务器）

> 面向零命令行基础也能照抄，每一步都给了可复制的命令。
> 全程分为四段：**GitHub 建仓 → 本地推送 → 服务器初始化 → 部署验证**。

---

## 第 0 步：前置清单

| 项目 | 说明 |
| --- | --- |
| 阿里云百炼 API Key | [bailian.console.aliyun.com](https://bailian.console.aliyun.com/) → 右上角头像 → API Key |
| searchapi Key（可选） | [searchapi.io](https://www.searchapi.io/) 注册，联网搜索工具要用 |
| 阿里云轻量服务器 | 建议 **2 核 2G** 起，系统 Ubuntu 22.04 |
| 安全组放行端口 | **80**（前端）、**22**（SSH）；8123 不要对外开 |

---

## 第 1 步：GitHub 建仓并推送

### 1.1 在 GitHub 上新建空仓库

打开 [github.com/new](https://github.com/new)，仓库名填 `yu-ai-agent`，可见性选 **Public**（实习简历要能点开），
**不要勾选** Add README / .gitignore / license（本地已有）。

### 1.2 本地初始化并推送

在本机项目根目录执行（把 `你的用户名` 换成你的 GitHub 用户名）：

```bash
cd /path/to/yu-ai-agent-2026

git init -b main
git add .

git -c user.name="你的名字" -c user.email="你的邮箱" commit -m "feat: 迁移至 Spring Boot 3.5.16 + Spring AI 1.1.8 + Spring AI Alibaba 1.1.2.2"

git remote add origin https://github.com/你的用户名/yu-ai-agent.git
git push -u origin main
```

> 推送时弹窗登录：用户名填 GitHub 用户名，密码填 **Personal Access Token**
> （GitHub → Settings → Developer settings → Tokens (classic) → 勾选 `repo`）。

### 1.3 验证 CI

推送后打开 `https://github.com/你的用户名/yu-ai-agent/actions`，
三个 Job（后端 / MCP 服务 / 前端）全绿代表依赖矩阵没问题。

---

## 第 2 步：服务器初始化（只做一次）

用阿里云控制台的「远程连接」或本地 SSH 登录服务器。

### 2.1 安装 Docker

```bash
curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
systemctl enable --now docker
docker -v && docker compose version
```

### 2.2 拉取代码并生成密钥文件

```bash
git clone https://github.com/你的用户名/yu-ai-agent.git /root/yu-ai-agent
cd /root/yu-ai-agent
chmod +x deploy.sh
./deploy.sh init
```

脚本会生成 `.env` 模板，编辑它填入真实 Key：

```bash
vim /root/yu-ai-agent/.env
```

```ini
AI_DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxx
SEARCH_API_KEY=xxxxxxxx
```

> `.env` 已在 `.gitignore` 中，**不会被提交**，密钥不会泄露到 GitHub。

---

## 第 3 步：一键部署

```bash
cd /root/yu-ai-agent && ./deploy.sh
```

脚本会自动：拉最新代码 → `docker compose up -d --build` → 轮询 `/api/health` 直到通过 → 清理悬空镜像。
首次构建约 5–10 分钟（要拉 Maven 依赖和前端 npm 包）。

### 验证

```bash
# 健康检查
curl http://127.0.0.1:8123/api/health          # 返回 ok

# 真实对话（等 10-20 秒）
curl "http://127.0.0.1:8123/api/ai/love_app/chat/sync?message=我和对象吵架了怎么办&chatId=demo1"

# 容器状态
docker compose ps
```

浏览器打开：
- 前端：`http://服务器公网IP`
- 接口文档：`http://服务器公网IP/api/doc.html`

---

## 方案 B：1G 内存小机器的部署方式（不用 Docker 构建）

Docker 构建期峰值内存较高，1G 机器容易 OOM。改用「本地打包 → 上传 → 直接跑」：

### B1 本地（你的电脑）打包

```bash
# 后端
./mvnw clean package -DskipTests
# 产物：target/yu-ai-agent.jar

# 前端
cd yu-ai-agent-frontend && npm install && npm run build
# 产物：dist/
```

### B2 上传到服务器

```bash
scp target/yu-ai-agent.jar root@服务器IP:/root/yu-ai-agent.jar
scp -r yu-ai-agent-frontend/dist root@服务器IP:/root/frontend
```

### B3 服务器上安装运行时并启动

```bash
# 安装 JRE + Nginx（服务器执行）
apt update && apt install -y openjdk-21-jre-headless nginx

# 建服务目录
mkdir -p /root/yu-ai-agent/{logs,tmp}

# 用 systemd 托管后端
cat > /etc/systemd/system/yu-ai-agent.service <<'EOF'
[Unit]
Description=yu-ai-agent
After=network.target

[Service]
Type=simple
Environment="AI_DASHSCOPE_API_KEY=sk-你的Key"
Environment="SEARCH_API_KEY=你的Key"
Environment="SPRING_PROFILES_ACTIVE=prod"
WorkingDirectory=/root/yu-ai-agent
ExecStart=/usr/bin/java -Xms256m -Xmx600m -jar /root/yu-ai-agent.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now yu-ai-agent
systemctl status yu-ai-agent
```

### B4 配置 Nginx

把仓库里的 `yu-ai-agent-frontend/nginx.conf` 复制到 `/etc/nginx/conf.d/yu-ai-agent.conf`，
把 `root` 改成 `/root/frontend;`，然后：

```bash
nginx -t && systemctl reload nginx
```

---

## 第 4 步：日常更新

代码推到 GitHub 后，服务器执行：

```bash
cd /root/yu-ai-agent && ./deploy.sh
```

其他常用命令：

```bash
./deploy.sh logs yu-ai-agent   # 看后端实时日志
./deploy.sh restart            # 重启
./deploy.sh stop               # 停止
```

---

## 排障速查表

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| 启动报 `No qualifying bean of type 'ChatModel'` | 没配 `spring.ai.model.chat: dashscope` | 检查 `application.yml` / `application-local.yml` 里那两行 |
| 启动报 `Could not find ... spring-ai-alibaba-starter-dashscope:` | BOM 漏管版本 | pom 里给该依赖显式写 `<version>1.1.2.2</version>` |
| 启动报 NoUniqueBean（ChatModel 有两个） | Ollama 与 DashScope 都注册了 | 确认 `spring.ai.model.chat` 只有一个值；注入点补 `@Qualifier` |
| SSE 流式输出一次性全出来 | nginx 缓冲没关 | nginx.conf 里 `proxy_buffering off;` 必须有 |
| 前端白屏 / 接口 404 | nginx 反代路径写错 | 确认 `proxy_pass http://127.0.0.1:8123/api/;` 结尾带 `/` |
| 阿里云返回 HTTP 400 url error | ChatOptions 被新建对象覆盖 | 用 `chatModel.getDefaultOptions()` 取基底（本项目已修） |
| 构建时 OOM | 内存不足 | 走方案 B，或给轻量服务器加 2G swap |
