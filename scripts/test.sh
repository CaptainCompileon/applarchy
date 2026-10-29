#!/bin/bash
# Smoke test (tests/smoke): every effect in every theme through the engine's C API, built as the
# app builds them. Run by .github/workflows/build.yml; locally after changing effects, themes or
# the engine.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/engine.sh
OUT=$(mktemp -d)
swiftc -O -module-name Smoke -import-objc-header saver/ttfx.h \
  tests/smoke/main.swift studio/Catalog.swift saver/Themes.swift saver/LogoArt.swift "$ENGINE_LIB" \
  -framework AppKit -framework CoreText -o "$OUT/smoke" 2>&1 | { grep -v '^ld: warning' || true; }
"$OUT/smoke"
