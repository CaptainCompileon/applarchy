#!/bin/bash
# Build Applarchy.app (with its screensaver inside) into dist/. A dev build by
# default ("Applarchy DEV.app"); APPLARCHY_FLAVOR=release for the released app.
set -euo pipefail
cd "$(dirname "$0")/.."
# Rust: rustup (on PATH, or Homebrew's keg-only one, as scripts/engine.sh finds it) or a cargo on PATH.
[ -x "${RUSTUP:-$(command -v rustup || echo /opt/homebrew/opt/rustup/bin/rustup)}" ] || command -v cargo >/dev/null \
  || { echo "error: Rust is required (https://rustup.rs, 'brew install rustup' or 'brew install rust')" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "error: Swift is required ('xcode-select --install')" >&2; exit 1; }
source scripts/flavor.sh
studio/build.sh
rm -rf dist && mkdir -p dist
cp -R "studio/build/$APP_NAME.app" dist/
echo "→ dist/$APP_NAME.app"
