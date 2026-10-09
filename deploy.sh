#!/usr/bin/env bash
# ============================================================
# yu-ai-agent 阿里云轻量服务器一键部署脚本
# 用法：
#   1) 首次：chmod +x deploy.sh && ./deploy.sh init
#   2) 日常更新：./deploy.sh
# ============================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/root/yu-ai-agent}"
REPO_URL="${REPO_URL:-https://github.com/yangyu3622/yu-ai-agent.git}"
BRANCH="${BRANCH:-master}"
COMPOSE="docker compose"

log()  { echo -e "\033[32m[INFO]\033[0m $*"; }
warn() { echo -e "\033[33m[WARN]\033[0m $*"; }
err()  { echo -e "\033[31m[ERROR]\033[0m $*"; exit 1; }

check_env() {
  command -v docker >/dev/null 2>&1 || err "未检测到 docker，请先安装：https://docs.docker.com/engine/install/"
  docker info >/dev/null 2>&1 || err "docker 守护进程未运行，执行 systemctl start docker"
  $COMPOSE version >/dev/null 2>&1 || err "未检测到 docker compose 插件（v2）"
}

init_all() {
  log "==> 初始化部署环境"
  mkdir -p "$APP_DIR/runtime/tmp" "$APP_DIR/runtime/logs"

  if [ ! -d "$APP_DIR/.git" ]; then
    log "==> 克隆仓库 $REPO_URL"
    git clone -b "$BRANCH" "$REPO_URL" "$APP_DIR"
  else
    log "==> 仓库已存在，跳过克隆"
  fi

  cd "$APP_DIR"

  if [ ! -f ".env" ]; then
    cat > .env <<'EOF'
# ===== 填写真实 Key，本文件已被 .gitignore 忽略，绝不提交 =====
AI_DASHSCOPE_API_KEY=sk-在这里填你的百炼Key
SEARCH_API_KEY=在这里填searchapi的Key
EOF
    warn "已生成 .env 模板，请 vim .env 填入真实 Key 后重新执行 ./deploy.sh"
    exit 0
  fi

  log "==> 初始化完成"
}

deploy() {
  check_env
  cd "$APP_DIR"

  [ -f ".env" ] || err "缺少 $APP_DIR/.env，请先执行 ./deploy.sh init 并填写 Key"

  log "==> 拉取最新代码（$BRANCH）"
  git fetch --all --prune
  git checkout "$BRANCH"
  git pull --ff-only origin "$BRANCH"

  log "==> 构建并启动容器（首次构建约 5-10 分钟）"
  $COMPOSE up -d --build --remove-orphans

  log "==> 等待后端健康检查通过"
  for i in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:8123/api/health >/dev/null 2>&1; then
      log "后端已就绪（耗时约 $((i * 5))s）"
      break
    fi
    [ "$i" -eq 40 ] && { err "后端启动超时，执行 docker compose logs yu-ai-agent 查看原因"; }
    sleep 5
  done

  log "==> 清理悬空镜像"
  docker image prune -f >/dev/null 2>&1 || true

  $COMPOSE ps
  log "部署完成 ✅  前端：http://服务器公网IP   接口文档：http://服务器公网IP/api/doc.html"
}

case "${1:-deploy}" in
  init)   init_all ;;
  deploy) deploy ;;
  logs)   cd "$APP_DIR" && $COMPOSE logs -f "${2:-yu-ai-agent}" ;;
  stop)   cd "$APP_DIR" && $COMPOSE down ;;
  restart) cd "$APP_DIR" && $COMPOSE restart ;;
  *)      echo "用法: $0 {init|deploy|logs [服务名]|stop|restart}" ; exit 1 ;;
esac
