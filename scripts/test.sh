#!/bin/bash
# The tests, run by .github/workflows/build.yml and locally after a change:
# - Smoke test (tests/smoke): every effect in every theme through the engine's C API, built as the
#   app builds them. For changes to effects, themes or the engine.
# - Unit tests (tests/unit): the app's own logic that needs no screen (Smooth Mode's handoff
#   arithmetic, the shared timeline, theme commands, saved settings, logo files, versions).
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/engine.sh
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
swiftc -O -module-name Smoke -import-objc-header saver/ttfx.h \
  tests/smoke/main.swift studio/Catalog.swift saver/Themes.swift saver/LogoArt.swift "$ENGINE_LIB" \
  -framework AppKit -framework CoreText -o "$OUT/smoke" 2>&1 | { grep -v '^ld: warning' || true; }
"$OUT/smoke"

# The effect view under the name the app compiles it as (studio/build.sh).
sed "s/ApplarchySaverView/StudioEffectView/g" saver/ApplarchySaverView.swift > "$OUT/StudioEffectView.swift"
swiftc -module-name Unit -import-objc-header saver/ttfx.h \
  tests/unit/main.swift "$OUT/StudioEffectView.swift" saver/PixelClock.swift saver/Themes.swift saver/LogoArt.swift \
  studio/Catalog.swift studio/Config.swift studio/LogoFile.swift studio/Updates.swift "$ENGINE_LIB" \
  -framework ScreenSaver -framework AppKit -framework CoreText -o "$OUT/unit" 2>&1 | { grep -v '^ld: warning' || true; }
"$OUT/unit"
