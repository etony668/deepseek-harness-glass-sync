#!/bin/sh
# 从 DeepSeek 官方 GitHub commit 构建完整 dsh web runtime，并原子切换。
# 由 App 菜单调用；Node/pnpm 均取自 App Resources，用户 DSH_HOME 不在范围内。
# stdout 仅输出机器可读的 @@DSH_SYNC@@ JSON 进度事件；完整命令日志保存在
# Application Support/runtime/latest-sync.log，避免把 curl/pnpm 原始日志塞进 UI。
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: $0 <runtime-root> <official-commit>" >&2
  exit 64
fi

RUNTIME_ROOT="$1"
COMMIT="$2"
RESOURCES="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NODE="$RESOURCES/node/node"
PNPM="$RESOURCES/pnpm/node_modules/pnpm/bin/pnpm.mjs"
MATERIALIZER="$RESOURCES/bin/materialize-runtime.mjs"
# 直连 GitHub 官方源码分发端点，避免 github.com/archive 的重定向链；
# 此 URL 与官方仓库的 commit 一一对应。
UPSTREAM_TARBALL="https://codeload.github.com/deepseek-ai/deepseek-harness/tar.gz/${COMMIT}"

case "$COMMIT" in
  *[!0123456789abcdef]*)
    echo "invalid official commit: $COMMIT" >&2
    exit 65
    ;;
esac
if [ "${#COMMIT}" -ne 40 ]; then
  echo "invalid official commit length: $COMMIT" >&2
  exit 65
fi

case "$RUNTIME_ROOT" in
  "$HOME/Library/Application Support/DeepSeek Harness Glass"/runtime) ;;
  *)
    echo "refusing runtime root outside DeepSeek Harness Glass Application Support" >&2
    exit 66
    ;;
esac

for required in "$NODE" "$PNPM" "$MATERIALIZER"; do
  if [ ! -f "$required" ]; then
    echo "missing bundled update tool: $required" >&2
    exit 67
  fi
done

VERSIONS="$RUNTIME_ROOT/versions"
TARGET="$VERSIONS/$COMMIT"
CURRENT="$RUNTIME_ROOT/current"
STAGE="$RUNTIME_ROOT/.staging-$COMMIT-$$"
DOWNLOADS="$RUNTIME_ROOT/downloads"
ARCHIVE="$DOWNLOADS/$COMMIT.tar.gz"
PARTIAL_ARCHIVE="$ARCHIVE.part"
SYNC_LOG="$RUNTIME_ROOT/latest-sync.log"
LAST_FRACTION="0"

runtime_complete() {
  test -f "$1/lib/bin.js" \
    && test -f "$1/package.json" \
    && test -f "$1/node_modules/@deepseek-ai/dsh-app-boot/package.json" \
    && test -f "$1/node_modules/@deepseek-ai/dsh-base/package.json" \
    && test -f "$1/node_modules/@deepseek-ai/dsh-web-app/package.json"
}

emit() {
  # $1 phase, $2 fraction, $3 title, $4 detail
  LAST_FRACTION="$2"
  printf '@@DSH_SYNC@@{"phase":"%s","fraction":%s,"title":"%s","detail":"%s"}\n' \
    "$1" "$2" "$3" "$4"
}

fail() {
  # $1 phase, $2 short Chinese error (shell-controlled, safe JSON text)
  emit "$1" "$LAST_FRACTION" "同步未完成" "$2"
  exit 1
}

mkdir -p "$RUNTIME_ROOT"
: > "$SYNC_LOG"

if [ -e "$TARGET" ] && ! runtime_complete "$TARGET"; then
  BROKEN_TARGET="$TARGET.broken-$(date +%Y%m%d-%H%M%S)-$$"
  mv -f "$TARGET" "$BROKEN_TARGET"
  printf 'invalid cached runtime moved to %s\n' "$BROKEN_TARGET" >> "$SYNC_LOG"
fi

if runtime_complete "$TARGET"; then
  emit "activate" "0.96" "正在激活已缓存的官方版本" "$COMMIT"
  LINK="$RUNTIME_ROOT/.current-$COMMIT-$$"
  ln -s "versions/$COMMIT" "$LINK"
  mv -f "$LINK" "$CURRENT"
  emit "complete" "1" "官方 Harness 已更新" "已启用已缓存的提交 ${COMMIT}"
  exit 0
fi

mkdir -p "$VERSIONS" "$DOWNLOADS"
rm -rf "$STAGE"
mkdir -p "$STAGE/source" "$STAGE/backend"
cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT HUP INT TERM

if [ -f "$ARCHIVE" ] && tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
  emit "download" "0.24" "正在准备官方源码" "已找到可用的本地下载缓存"
else
  rm -f "$ARCHIVE"
  emit "download" "0.08" "正在下载官方源码" "从 GitHub 官方源下载；中断后可继续"
  # 保留 .part 文件，在弱网下可从上次已下载的字节继续，而不是重新开始。
  curl -fL -sS \
    --continue-at - \
    --retry 4 \
    --retry-all-errors \
    --retry-delay 2 \
    --connect-timeout 20 \
    --max-time 1800 \
    --speed-time 120 \
    --speed-limit 1024 \
    "$UPSTREAM_TARBALL" \
    -o "$PARTIAL_ARCHIVE" >> "$SYNC_LOG" 2>&1 &
  CURL_PID=$!
  while kill -0 "$CURL_PID" 2>/dev/null; do
    if [ -f "$PARTIAL_ARCHIVE" ]; then
      BYTES="$(wc -c < "$PARTIAL_ARCHIVE" | tr -d ' ')"
      MEGABYTES=$((BYTES / 1048576))
      emit "download" "0.14" "正在下载官方源码" "已下载 ${MEGABYTES} MB；网络较慢时可稍后继续"
    fi
    sleep 1
  done
  if ! wait "$CURL_PID"; then
    fail "download" "官方下载未完成；请检查网络后再次同步，已下载部分会自动续传。"
  fi
  mv -f "$PARTIAL_ARCHIVE" "$ARCHIVE"
fi

emit "extract" "0.27" "正在解压官方源码" "正在验证并展开提交 ${COMMIT}"
if ! tar -xzf "$ARCHIVE" -C "$STAGE/source" --strip-components=1 >> "$SYNC_LOG" 2>&1; then
  rm -f "$ARCHIVE"
  fail "extract" "下载的官方源码包校验失败，已丢弃缓存；请再次同步。"
fi

if [ ! -f "$STAGE/source/package.json" ] || [ ! -f "$STAGE/source/pnpm-lock.yaml" ]; then
  fail "extract" "官方源码包不完整，已保留诊断日志。"
fi

run_pnpm() {
  CI=true "$NODE" "$PNPM" "$@"
}

emit "install" "0.34" "正在安装官方依赖" "首次同步可能需要几分钟"
if ! (
  cd "$STAGE/source"
  run_pnpm install --frozen-lockfile
) >> "$SYNC_LOG" 2>&1; then
  fail "install" "官方依赖安装失败；请检查网络后重试。"
fi

emit "build" "0.56" "正在构建官方 Harness" "正在编译 Web Profile 与插件运行时"
if ! (
  cd "$STAGE/source"
  # GitHub codeload 的 commit tarball 不带 .git 目录，而官方构建会把
  # 源码提交写入浏览器产物。这里传入已经由 App 查询并用于下载的同一
  # 官方 commit，等价于源码检出的 HEAD，且无需伪造/修改上游仓库。
  CI=true DSH_CLIENT_COMMIT_HASH="$COMMIT" "$NODE" "$PNPM" run build
) >> "$SYNC_LOG" 2>&1; then
  fail "build" "官方源码构建失败；已保留诊断日志。"
fi

emit "deploy" "0.76" "正在打包完整运行时" "正在准备官方 dsh 与所有 Profile Bundle"
if ! (
  cd "$STAGE/source"
  run_pnpm --filter @deepseek-ai/dsh deploy --prod --legacy \
    --config.node-linker=hoisted "$STAGE/backend"
) >> "$SYNC_LOG" 2>&1; then
  fail "deploy" "官方运行时打包失败；已保留诊断日志。"
fi

runtime_complete "$STAGE/backend" || {
  fail "deploy" "官方 dsh 入口缺失，无法启用该版本。"
}

emit "materialize" "0.90" "正在整理运行时文件" "正在校验官方 workspace 依赖闭包"
if ! "$NODE" "$MATERIALIZER" "$STAGE/source" "$STAGE/backend" >> "$SYNC_LOG" 2>&1; then
  fail "materialize" "运行时依赖整理失败；已保留诊断日志。"
fi

runtime_complete "$STAGE/backend" || {
  fail "materialize" "整理后缺少官方 dsh 入口，无法启用该版本。"
}

printf '{\n  "upstream": "https://github.com/deepseek-ai/deepseek-harness",\n  "commit": "%s"\n}\n' \
  "$COMMIT" > "$STAGE/backend/.deepseek-harness-glass-runtime.json"

rm -rf "$TARGET"
mv "$STAGE/backend" "$TARGET"
emit "activate" "0.98" "正在启用官方 Harness" "正在原子切换到新版本"
LINK="$RUNTIME_ROOT/.current-$COMMIT-$$"
ln -s "versions/$COMMIT" "$LINK"
mv -f "$LINK" "$CURRENT"

emit "complete" "1" "官方 Harness 已更新" "已启用提交 ${COMMIT}"
