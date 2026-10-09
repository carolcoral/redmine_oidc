#!/usr/bin/env bash
# 质量阀门：跑全部单元测试并强制行覆盖率 ≥ 80%。
#
# 覆盖率阈值同时在 test/run.rb（SimpleCov.minimum_coverage）与这里设置：
# 前者保证本地与 CI 口径一致，后者让脚本在覆盖率不足时以非零退出码失败，
# 从而中断流水线。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

COVERAGE_MIN="${COVERAGE_MIN:-80}"

echo "==> 运行单元测试（覆盖率阈值 ${COVERAGE_MIN}%）"
ruby -Ilib -Itest test/run.rb

# SimpleCov 已按 coverage/.last_run.json 记录行覆盖率，这里再显式校验一次，
# 防止未来改动 SimpleCov 配置导致阈值被静默绕过。
LAST_RUN="coverage/.last_run.json"
if [[ -f "$LAST_RUN" ]]; then
  COVERAGE="$(ruby -U -rjson -e 'puts JSON.parse(File.read(ARGV[0]))["result"]["line"]' "$LAST_RUN")"
  echo "==> 行覆盖率：${COVERAGE}%"
  if ruby -U -e "exit(ARGV[0].to_f >= ARGV[1].to_f ? 0 : 1)" "$COVERAGE" "$COVERAGE_MIN"; then
    echo "==> 覆盖率达标（≥ ${COVERAGE_MIN}%）"
  else
    echo "!! 覆盖率 ${COVERAGE}% 低于阈值 ${COVERAGE_MIN}%" >&2
    exit 1
  fi
else
  echo "!! 未生成覆盖率报告（$LAST_RUN），无法校验阈值" >&2
  exit 1
fi

# Ruby 语法检查：捕获测试未加载到的文件（视图辅助、控制器等）中的低级错误。
echo "==> Ruby 语法检查"
while IFS= read -r file; do
  ruby -c "$file" >/dev/null
done < <(find app lib config init.rb -name '*.rb' -type f 2>/dev/null)
echo "==> 语法检查通过"

# 本地化文件必须可解析，且中英文键完全对齐。
echo "==> 校验本地化文件"
ruby -U scripts/check_locales.rb

echo "==> 质量阀门通过"
