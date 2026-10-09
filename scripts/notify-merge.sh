#!/usr/bin/env bash
# 合并后回调：记录本次合并部署的上下文，便于事后追溯。
set -euo pipefail

echo "==> 分支 $CNB_BRANCH 已合并（commit ${CNB_COMMIT_SHORT:-unknown}）"
echo "    仓库：${CNB_REPO_SLUG:-unknown}"
echo "    构建：${CNB_BUILD_ID:-unknown}"
echo "    触发人：${CNB_COMMITTER:-unknown}"
