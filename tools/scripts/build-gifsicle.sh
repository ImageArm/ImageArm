#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="$ROOT/tools/submodules/gifsicle"
BIN="$ROOT/tools/bin"
OUT="$BIN/gifsicle"

mkdir -p "$BIN"

echo "🔨 Compilation gifsicle (C/autotools, arm64)..."

if [ ! -d "$SRC/.git" ] && [ ! -f "$SRC/configure.ac" ]; then
  echo "  ❌ Submodule gifsicle non initialisé : git submodule update --init tools/submodules/gifsicle"
  exit 1
fi

cd "$SRC"

if [ ! -x "./configure" ]; then
  echo "  🔧 autoreconf -i..."
  autoreconf -i
fi

echo "  🔧 ./configure..."
CFLAGS="-arch arm64 -mmacosx-version-min=14.0 -O2" \
LDFLAGS="-arch arm64 -mmacosx-version-min=14.0" \
./configure \
  --disable-gifview \
  --disable-gifdiff

echo "  🔧 make..."
make -j"$(sysctl -n hw.ncpu)"

cp -f src/gifsicle "$OUT"
chmod +x "$OUT"

echo "  ✅ gifsicle compilé : $(du -h "$OUT" | awk '{print $1}') — $(file "$OUT")"
