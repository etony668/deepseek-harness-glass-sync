#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OUT="$ROOT/build/bin"
mkdir -p "$OUT"

cat > "$OUT/pnpm" <<'EOF'
#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$HERE/../node/node" "$HERE/../pnpm/node_modules/pnpm/bin/pnpm.mjs" "$@"
EOF
chmod +x "$OUT/pnpm"

cat > "$OUT/pnpx" <<'EOF'
#!/bin/sh
set -eu
HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
exec "$HERE/../node/node" "$HERE/../pnpm/node_modules/pnpm/bin/pnpx.mjs" "$@"
EOF
chmod +x "$OUT/pnpx"
