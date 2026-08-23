#!/bin/sh
set -eu

# Build the official Harness source checkout and prepare the exact runtime
# closure embedded by DeepSeek Harness Glass. The Swift shell never replaces
# the official profile/plugin runtime; it launches the deployed @deepseek-ai/dsh
# package produced here.

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HARNESS="$ROOT/upstream/deepseek-harness"
BUILD="$ROOT/glass/build"
VERSIONS="$ROOT/glass/runtime/versions.env"

if [ ! -f "$VERSIONS" ]; then
  echo "missing embedded runtime versions file: $VERSIONS" >&2
  exit 1
fi
# shellcheck source=../glass/runtime/versions.env
. "$VERSIONS"
NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-arm64.tar.gz"
NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}"

if [ ! -f "$HARNESS/package.json" ]; then
  git -C "$ROOT" submodule update --init --checkout upstream/deepseek-harness
fi

if [ ! -x "$BUILD/node/node" ] \
  || [ ! -f "$BUILD/npm/node_modules/npm/bin/npm-cli.js" ]; then
  mkdir -p "$BUILD/node" "$BUILD/npm/node_modules"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT HUP INT TERM
  curl -fsSL "$NODE_URL" -o "$tmp/node.tgz"
  tar -xzf "$tmp/node.tgz" -C "$tmp"
  cp "$tmp/node-v${NODE_VERSION}-darwin-arm64/bin/node" "$BUILD/node/node"
  chmod +x "$BUILD/node/node"
  rm -rf "$BUILD/npm/node_modules/npm"
  cp -RL "$tmp/node-v${NODE_VERSION}-darwin-arm64/lib/node_modules/npm" \
    "$BUILD/npm/node_modules/npm"
fi

mkdir -p "$BUILD/pnpm"
if [ ! -f "$BUILD/pnpm/package.json" ] \
  || [ "$("$BUILD/node/node" -p "try { require('$BUILD/pnpm/package.json').version } catch { '' }")" != "$PNPM_VERSION" ]; then
  rm -rf "$BUILD/pnpm"
  mkdir -p "$BUILD/pnpm"
  "$BUILD/node/node" "$BUILD/npm/node_modules/npm/bin/npm-cli.js" \
    install --prefix "$BUILD/pnpm" --omit=dev --no-audit --no-fund "pnpm@${PNPM_VERSION}"
fi

run_pnpm() {
  CI=true "$BUILD/node/node" "$BUILD/pnpm/node_modules/pnpm/bin/pnpm.mjs" "$@"
}

if [ ! -f "$HARNESS/pnpm-lock.yaml" ]; then
  echo "missing upstream lockfile: $HARNESS/pnpm-lock.yaml" >&2
  exit 1
fi

echo "== official Harness: install =="
(
  cd "$HARNESS"
  run_pnpm install --frozen-lockfile
  run_pnpm run build
)

echo "== official Harness: deploy @deepseek-ai/dsh runtime =="
rm -rf "$BUILD/backend"
mkdir -p "$BUILD/backend"
(
  cd "$HARNESS"
  # `pnpm deploy` materializes the CLI package plus its complete production
  # dependency closure, including the web frontend and every shipped bundle.
  # The upstream workspace intentionally keeps normal symlinked workspace
  # dependencies. pnpm 11 requires injected workspace packages for the new
  # deploy mode; `--legacy` is the supported way to deploy this unchanged
  # official checkout while still materializing the full production closure.
  run_pnpm --filter @deepseek-ai/dsh deploy --prod --legacy \
    --config.node-linker=hoisted "$BUILD/backend"
)

test -f "$BUILD/backend/lib/bin.js" || {
  echo "deployed dsh entry missing: $BUILD/backend/lib/bin.js" >&2
  exit 1
}

echo "== materialize official workspace peer closure =="
"$BUILD/node/node" "$ROOT/scripts/materialize-runtime.mjs"

"$ROOT/glass/runtime/make-pnpm-wrapper.sh"

echo "== smoke test official dsh web profile =="
TMP_HOME="$(mktemp -d)"
LOG="$BUILD/dsh-smoke.log"
DSH_HOME="$TMP_HOME" "$BUILD/node/node" --expose-internals \
  "$BUILD/backend/lib/bin.js" web --no-open --port 0 >"$LOG" 2>&1 &
PID=$!
cleanup() {
  kill "$PID" 2>/dev/null || true
  wait "$PID" 2>/dev/null || true
  rm -rf "$TMP_HOME"
}
trap cleanup EXIT HUP INT TERM

i=0
while [ "$i" -lt 30 ]; do
  if grep -Eq 'dsh web: http://127\.0\.0\.1:[0-9]+' "$LOG"; then
    echo "official dsh web smoke test passed"
    exit 0
  fi
  if ! kill -0 "$PID" 2>/dev/null; then
    cat "$LOG" >&2
    exit 1
  fi
  i=$((i + 1))
  sleep 1
done

cat "$LOG" >&2
echo "timed out waiting for official dsh web profile" >&2
exit 1
