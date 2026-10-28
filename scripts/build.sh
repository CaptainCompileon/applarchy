#!/bin/bash
# Build Applarchy.app (with its screensaver inside) into dist/. A dev build by
# default ("Applarchy DEV.app"); APPLARCHY_FLAVOR=release for the released app.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v cargo >/dev/null || { echo "error: Rust is required (https://rustup.rs or 'brew install rust')" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "error: Swift is required ('xcode-select --install')" >&2; exit 1; }
source scripts/flavor.sh
studio/build.sh
rm -rf dist && mkdir -p dist
cp -R "studio/build/$APP_NAME.app" dist/
echo "→ dist/$APP_NAME.app"
