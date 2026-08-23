#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SUBMODULE="$ROOT/upstream/deepseek-harness"

if [ ! -d "$SUBMODULE/.git" ] && [ ! -f "$SUBMODULE/.git" ]; then
  git -C "$ROOT" submodule update --init --checkout upstream/deepseek-harness
fi

git -C "$SUBMODULE" fetch --prune origin master
git -C "$SUBMODULE" checkout --detach origin/master

printf 'DeepSeek Harness upstream is now at '
git -C "$SUBMODULE" rev-parse --short HEAD
git -C "$SUBMODULE" describe --tags --always
