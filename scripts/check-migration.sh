#!/usr/bin/env bash
# 迁移自检：部署前确认数据库迁移文件可被解析、且版本号不重复。
#
# 正式环境部署会执行 `rake redmine:plugins:migrate`，迁移一旦有语法错误或
# 版本冲突，会导致 Redmine 启动失败。这里用轻量检查提前拦截。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MIGRATION_DIR="db/migrate"

if [[ ! -d "$MIGRATION_DIR" ]]; then
  echo "==> 未发现迁移目录，跳过"
  exit 0
fi

echo "==> 检查迁移文件语法"
shopt -s nullglob
migrations=("$MIGRATION_DIR"/*.rb)
if [[ ${#migrations[@]} -eq 0 ]]; then
  echo "==> 无迁移文件"
  exit 0
fi

for file in "${migrations[@]}"; do
  ruby -c "$file" >/dev/null
  echo "  ok  $file"
done

echo "==> 检查迁移版本号唯一性"
versions="$(printf '%s\n' "${migrations[@]}" | xargs -n1 basename | cut -d_ -f1 | sort)"
duplicates="$(printf '%s\n' "$versions" | uniq -d)"
if [[ -n "$duplicates" ]]; then
  echo "!! 迁移版本号重复：$duplicates" >&2
  exit 1
fi

echo "==> 迁移检查通过（共 ${#migrations[@]} 个）"
