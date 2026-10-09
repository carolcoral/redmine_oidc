#!/usr/bin/env bash
# 部署后冒烟测试：确认正式环境已经起来、且 OIDC 路由可达。
#
# 只做只读探测，不触发登录流程——真正走完 OIDC 需要交互式浏览器。
# 探测失败即视为部署失败，让流水线变红而不是静默通过。
set -euo pipefail

: "${REDMINE_URL:?缺少 REDMINE_URL（正式环境访问地址）}"

TIMEOUT="${SMOKE_TIMEOUT:-60}"
INTERVAL=5
EXPECTED_STATUS="${SMOKE_EXPECTED_STATUS:-200}"

echo "==> 等待 ${REDMINE_URL} 就绪（最多 ${TIMEOUT}s）"
deadline=$((SECONDS + TIMEOUT))
status=""
while (( SECONDS < deadline )); do
  status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$REDMINE_URL/" || true)"
  if [[ "$status" == "$EXPECTED_STATUS" ]]; then
    echo "==> 站点已就绪（HTTP $status）"
    break
  fi
  echo "    当前 HTTP $status，${INTERVAL}s 后重试"
  sleep "$INTERVAL"
done

if [[ "$status" != "$EXPECTED_STATUS" ]]; then
  echo "!! 站点未在 ${TIMEOUT}s 内就绪（最后状态 HTTP $status）" >&2
  exit 1
fi

echo "==> 探测 OIDC 路由"
# 未登录访问 /oidc/login 应当被重定向到 IdP（302），或至少不是 5xx。
oidc_status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$REDMINE_URL/oidc/login" || true)"
case "$oidc_status" in
  2*|3*)
    echo "==> OIDC 路由正常（HTTP $oidc_status）"
    ;;
  401|403)
    echo "==> OIDC 路由存在但需要登录（HTTP $oidc_status），视为正常"
    ;;
  *)
    echo "!! OIDC 路由异常（HTTP $oidc_status）" >&2
    exit 1
    ;;
esac

echo "==> 冒烟测试通过"
