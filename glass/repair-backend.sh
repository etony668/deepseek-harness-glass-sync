#!/bin/bash
# 一键从官方源码重建完整 Harness runtime + 冒烟验证 + 重新打包
# 场景：App 报启动失败、上游更新后需要生成新的内置 runtime 时，运行本脚本即可修复。
# 用法: ./repair-backend.sh
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT/.."

echo "== 1/2 从官方源码构建完整 Harness runtime =="
./scripts/build-runtime.sh

echo "== 2/2 重新打包 Glass App =="
cd "$ROOT"
./assemble.sh 2>&1 | tail -3
echo "✅ 官方 Harness runtime 已重建，App 已重新打包"
