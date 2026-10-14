#!/bin/bash
# Build Applarchy.app (with its screensaver inside) into dist/.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v cargo >/dev/null || { echo "error: Rust is required (https://rustup.rs or 'brew install rust')" >&2; exit 1; }
command -v swiftc >/dev/null || { echo "error: Swift is required ('xcode-select --install')" >&2; exit 1; }
studio/build.sh
rm -rf dist && mkdir -p dist
cp -R studio/build/Applarchy.app dist/
echo "→ dist/Applarchy.app"
