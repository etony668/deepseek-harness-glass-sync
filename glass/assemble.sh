#!/bin/bash
# 组装原生玻璃壳 .app：编译 Swift + 内置 Node/pnpm + 官方 dsh runtime + 图标 + 签名
# 构建进暂存目录后原子替换，避免运行中的实例读到半成品文件。
# 输出位置：/Applications（唯一安装位置，避免 Spotlight 出现多个副本）。
set -e
cd "$(dirname "$0")"

# 输出位置：默认 /Applications（本机安装）；CI 可用 APP_PATH 覆盖
APP="${APP_PATH:-/Applications/DeepSeek Harness.app}"
STAGE="$(dirname "$APP")/.app-staging"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"

echo "== 1/4 编译 Swift 壳 =="
swiftc -O -parse-as-library -target arm64-apple-macosx26.0 \
  Sources/main.swift \
  -o "$STAGE/Contents/MacOS/DeepSeek Harness"

echo "== 2/4 内置固定版本 Node + pnpm =="
mkdir -p "$STAGE/Contents/Resources/node"
cp build/node/node "$STAGE/Contents/Resources/node/node"
chmod +x "$STAGE/Contents/Resources/node/node"
cp -RL build/pnpm "$STAGE/Contents/Resources/pnpm"
mkdir -p "$STAGE/Contents/Resources/bin"
cp build/bin/pnpm build/bin/pnpx "$STAGE/Contents/Resources/bin/"
cp runtime/sync-official-runtime.sh "$STAGE/Contents/Resources/bin/sync-official-runtime"
cp ../scripts/materialize-runtime.mjs "$STAGE/Contents/Resources/bin/materialize-runtime.mjs"
chmod +x \
  "$STAGE/Contents/Resources/bin/pnpm" \
  "$STAGE/Contents/Resources/bin/pnpx" \
  "$STAGE/Contents/Resources/bin/sync-official-runtime"

echo "== 3/4 内置官方 dsh profile 运行时 =="
cp -RL "build/backend" "$STAGE/Contents/Resources/backend"
test -f "$STAGE/Contents/Resources/backend/lib/bin.js"
git -C ../upstream/deepseek-harness rev-parse HEAD \
  > "$STAGE/Contents/Resources/bundled-runtime-commit"

echo "== 4/4 Info.plist / 图标 / 签名 / 原子替换 =="
cp Info.plist "$STAGE/Contents/Info.plist"
cp ../build/icon.icns "$STAGE/Contents/Resources/icon.icns"
cp assets/fish.svg "$STAGE/Contents/Resources/fish.svg"
codesign --force --deep -s - "$STAGE"

rm -rf "$APP"
mv "$STAGE" "$APP"

echo "== 完成 =="
du -sh "$APP"
