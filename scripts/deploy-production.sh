#!/usr/bin/env bash
# 正式环境部署：把插件部署到生产 Redmine 并完成迁移与重启。
#
# 走 SSH + rsync 而非容器编排，是因为正式环境是既有的 Redmine 实例，
# 只要求「把插件目录放到 plugins/redmine_oidc 并跑迁移重启」。
#
# 需要的环境变量（由 .cnb.yml 的 imports 从组织密钥仓库注入）：
#   DEPLOY_HOST       正式环境主机
#   DEPLOY_USER       SSH 用户
#   DEPLOY_PORT       SSH 端口（默认 22）
#   DEPLOY_SSH_KEY    SSH 私钥内容
#   REDMINE_HOME      正式环境 Redmine 根目录
#   REDMINE_SERVICE   Redmine 服务名（systemd / supervisor 均可）
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${DEPLOY_HOST:?缺少 DEPLOY_HOST}"
: "${DEPLOY_USER:?缺少 DEPLOY_USER}"
: "${REDMINE_HOME:?缺少 REDMINE_HOME}"
: "${DEPLOY_SSH_KEY:?缺少 DEPLOY_SSH_KEY}"

DEPLOY_PORT="${DEPLOY_PORT:-22}"
REDMINE_SERVICE="${REDMINE_SERVICE:-redmine}"
PLUGIN_NAME="redmine_oidc"
REMOTE_PLUGIN_DIR="$REDMINE_HOME/plugins/$PLUGIN_NAME"

echo "==> 部署 ${PLUGIN_NAME} 到 ${DEPLOY_USER}@${DEPLOY_HOST}:${REMOTE_PLUGIN_DIR}"

# 私钥写入受限临时文件，退出时清除，避免留在构建机磁盘上。
KEY_FILE="$(mktemp)"
chmod 600 "$KEY_FILE"
trap 'rm -f "$KEY_FILE"' EXIT
printf '%s\n' "$DEPLOY_SSH_KEY" > "$KEY_FILE"

SSH_OPTS=(-i "$KEY_FILE" -p "$DEPLOY_PORT"
          -o StrictHostKeyChecking=accept-new
          -o BatchMode=yes
          -o ConnectTimeout=15)

RSYNC_SSH="ssh ${SSH_OPTS[*]}"

# 只同步插件代码，排除本地测试产物与版本控制元数据。
rsync -az --delete \
  -e "$RSYNC_SSH" \
  --exclude '.git*' \
  --exclude 'coverage/' \
  --exclude 'tmp/' \
  --exclude 'log/' \
  ./ "$DEPLOY_USER@$DEPLOY_HOST:$REMOTE_PLUGIN_DIR/"

echo "==> 执行数据库迁移"
# --nobundle 让迁移使用 Redmine 既有的 bundle 环境；失败直接中断，避免重启到半成品。
ssh "${SSH_OPTS[@]}" "$DEPLOY_USER@$DEPLOY_HOST" bash -s <<REMOTE
set -euo pipefail
cd "$REDMINE_HOME"
export RAILS_ENV=production
if [[ -x ./bin/bundle ]]; then
  ./bin/bundle exec rake redmine:plugins:migrate NAME=$PLUGIN_NAME
else
  bundle exec rake redmine:plugins:migrate NAME=$PLUGIN_NAME
fi
REMOTE

echo "==> 重启 Redmine（$REDMINE_SERVICE）"
ssh "${SSH_OPTS[@]}" "$DEPLOY_USER@$DEPLOY_HOST" bash -s <<REMOTE
set -euo pipefail
if command -v systemctl >/dev/null 2>&1; then
  sudo -n systemctl restart "$REDMINE_SERVICE"
elif command -v supervisorctl >/dev/null 2>&1; then
  supervisorctl restart "$REDMINE_SERVICE"
else
  # 兜底：多数 Passenger 部署靠 tmp/restart.txt 触发平滑重启。
  touch "$REDMINE_HOME/tmp/restart.txt"
fi
REMOTE

echo "==> 部署完成"
