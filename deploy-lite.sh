#!/usr/bin/env bash
# ============================================================
# yu-ai-agent 轻量服务器（2G 内存）无 Docker 部署脚本
# 适用：不想/不能用 Docker 构建的小内存机器
# 前提：jar、dist 已上传到 /root
#
# 内存分配（2GiB 机器）：
#   JVM 堆 768MB + 元空间/线程栈约 250MB ≈ 1GB
#   nginx + 系统 ≈ 600MB
#   余量 ≈ 400MB，可从容应对并发请求
#   另配 2GB swap 作为兜底，防止峰值 OOM
#
# 用法：
#   ./deploy-lite.sh install   首次安装（装 JRE+nginx、配 systemd、启动）
#   ./deploy-lite.sh restart   重启服务
#   ./deploy-lite.sh logs      看实时日志
#   ./deploy-lite.sh status    看运行状态
#   ./deploy-lite.sh stop      停止服务
# ============================================================
set -euo pipefail

JAR="/root/yu-ai-agent.jar"
FRONTEND="/root/frontend"
LOGS="/root/yu-ai-agent/logs"
TMP="/root/yu-ai-agent/tmp"
SERVICE="yu-ai-agent"
# 2G 内存机器：堆 768m，留足余量给系统和其他进程
JAVA_OPTS="-Xms512m -Xmx768m -XX:+UseG1GC -XX:MaxMetaspaceSize=256m -Dfile.encoding=UTF-8"

log()  { echo -e "\033[32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[31m[ERROR]\033[0m $*"; exit 1; }

# ---------- 加 swap（1G 内存必备）----------
setup_swap() {
  if swapon --show | grep -q swapfile; then
    log "swap 已存在，跳过"
    return
  fi
  log "==> 创建 2G swap（兜底防峰值 OOM）"
  fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  # swappiness=10：尽量用内存，内存真不够了才用 swap
  sysctl -w vm.swappiness=10 >/dev/null
  grep -q 'vm.swappiness' /etc/sysctl.conf || echo 'vm.swappiness=10' >> /etc/sysctl.conf
  log "swap 创建完成"
}

# ---------- 安装依赖 ----------
detect_pm() {
  if command -v dnf >/dev/null 2>&1; then echo dnf
  elif command -v yum >/dev/null 2>&1; then echo yum
  elif command -v apt-get >/dev/null 2>&1; then echo apt
  else err "未识别的包管理器"; fi
}

install_deps() {
  local pm; pm=$(detect_pm)
  log "==> 检测到包管理器：$pm"

  if [ "$pm" = "apt" ]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq openjdk-21-jre-headless nginx curl wget fontconfig
    apt-get install -y -qq fonts-wqy-zenhei fonts-wqy-microhei || true
  else
    # RHEL / Alibaba Cloud Linux / CentOS
    $pm install -y -q java-21-openjdk-headless nginx curl wget fontconfig || \
      $pm install -y -q java-21-openjdk nginx curl wget fontconfig
    # 中文字体：PDF 生成工具需要，否则中文全是方块
    $pm install -y -q wqy-zenhei-fonts wqy-microhei-fonts || \
      $pm install -y -q google-noto-sans-cjk-fonts || true
  fi

  fc-cache -f >/dev/null 2>&1 || true
  log "==> 运行时安装完成：$(java -version 2>&1 | head -1)"
}

# ---------- RHEL 系专属：关 SELinux + 开防火墙 ----------
setup_rhel_security() {
  command -v getenforce >/dev/null 2>&1 || return 0
  log "==> 检查 SELinux / 防火墙（RHEL 系专属）"

  # SELinux enforcing 会阻止 nginx 反代后端端口，必须放行
  if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
    setenforce 0 2>/dev/null || true
    sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
    log "SELinux 已关闭（否则 nginx 无法反代 8123）"
  fi

  if command -v firewall-cmd >/dev/null 2>&1; then
    systemctl enable --now firewalld >/dev/null 2>&1 || true
    firewall-cmd --permanent --add-service=http >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    log "防火墙已放行 80"
  fi
}

# ---------- 询问并写入环境变量 ----------
ask_keys() {
  local env_file="/root/yu-ai-agent.env"
  if [ -f "$env_file" ]; then
    log "环境变量文件已存在，如需修改请直接编辑 $env_file"
    return
  fi
  echo ""
  read -r -p "请输入阿里云百炼 API Key（sk- 开头）: " DASHSCOPE_KEY
  [ -z "${DASHSCOPE_KEY:-}" ] && err "API Key 不能为空"
  read -r -p "请输入 searchapi Key（可留空，只影响联网搜索）: " SEARCH_KEY || true

  cat > "$env_file" <<EOF
AI_DASHSCOPE_API_KEY=${DASHSCOPE_KEY}
SEARCH_API_KEY=${SEARCH_KEY:-}
EOF
  chmod 600 "$env_file"
  log "环境变量已写入 $env_file（权限 600）"
}

# ---------- 配置 systemd ----------
setup_service() {
  log "==> 配置 systemd 服务"
  mkdir -p "$LOGS" "$TMP"
  cat > "/etc/systemd/system/${SERVICE}.service" <<EOF
[Unit]
Description=yu-ai-agent
After=network.target

[Service]
Type=simple
User=root
EnvironmentFile=/root/yu-ai-agent.env
Environment="SPRING_PROFILES_ACTIVE=prod"
Environment="LOG_DIR=${LOGS}"
WorkingDirectory=/root/yu-ai-agent
ExecStart=/usr/bin/java ${JAVA_OPTS} -jar ${JAR}
Restart=always
RestartSec=10
StandardOutput=append:${LOGS}/stdout.log
StandardError=append:${LOGS}/stderr.log

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null
  systemctl restart "$SERVICE"
}

# ---------- 配置 nginx ----------
setup_nginx() {
  log "==> 配置 nginx"
  cat > /etc/nginx/conf.d/yu-ai-agent.conf <<'EOF'
server {
    listen       80;
    server_name  _;

    root   /root/frontend;
    index  index.html;

    gzip on;
    gzip_min_length 1k;
    gzip_types text/plain text/css application/json application/javascript text/xml image/svg+xml;
    gzip_vary on;

    # Vue history 路由：刷新不 404
    location / {
        try_files $uri $uri/ /index.html;
    }

    # 反代后端（SSE 流式必需配置）
    location ^~ /api/ {
        proxy_pass http://127.0.0.1:8123/api/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_set_header Connection "";
        proxy_http_version 1.1;
        proxy_buffering off;      # 不关就丢失打字机效果
        proxy_cache off;
        chunked_transfer_encoding off;
        proxy_read_timeout 600s;
        proxy_send_timeout 600s;
    }

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf)$ {
        expires 1y;
        access_log off;
    }
}
EOF
  # 清掉默认站点，避免抢占 80 端口
  rm -f /etc/nginx/sites-enabled/default 2>/dev/null || true
  # RHEL 系默认 server 写在 nginx.conf 里，把它改到 8081 避免冲突
  if grep -qE "listen[[:space:]]+80" /etc/nginx/nginx.conf 2>/dev/null; then
    cp -n /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak 2>/dev/null || true
    sed -i 's/listen[[:space:]]\+80/listen       8081/' /etc/nginx/nginx.conf 2>/dev/null || true
    log "已将 nginx.conf 默认站点改到 8081"
  fi

  nginx -t || err "nginx 配置有误，请检查"
  systemctl enable nginx >/dev/null
  systemctl restart nginx
}

# ---------- 等待健康检查 ----------
wait_health() {
  log "==> 等待后端就绪（首次约 40-90 秒，需灌向量库）"
  for i in $(seq 1 60); do
    if curl -fsS http://127.0.0.1:8123/api/health >/dev/null 2>&1; then
      log "后端已就绪（约 $((i * 3))s）✅"
      return
    fi
    sleep 3
  done
  warn "健康检查超时，执行 ./deploy-lite.sh logs 查看原因"
}

install_all() {
  [ -f "$JAR" ] || err "缺少 $JAR，请先用 scp 上传"
  [ -d "$FRONTEND" ] || err "缺少 $FRONTEND，请先用 scp 上传 dist"

  setup_swap
  install_deps
  setup_rhel_security
  ask_keys
  setup_service
  setup_nginx
  wait_health

  echo ""
  log "部署完成 ✅"
  log "前端访问：http://服务器公网IP"
  log "接口文档：http://服务器公网IP/api/doc.html"
}

case "${1:-install}" in
  install) install_all ;;
  restart) systemctl restart "$SERVICE" && log "已重启" ;;
  stop)    systemctl stop "$SERVICE" && log "已停止" ;;
  start)   systemctl start "$SERVICE" && log "已启动" ;;
  status)  systemctl status "$SERVICE" --no-pager ;;
  logs)    journalctl -u "$SERVICE" -f --no-pager ;;
  *)       echo "用法: $0 {install|restart|stop|start|status|logs}"; exit 1 ;;
esac
