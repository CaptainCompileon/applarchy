#!/bin/bash
# Package dist/Applarchy.app as dist/Applarchy-<version>.dmg (drag to Applications).
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
# Uses dist/Applarchy.app as it is (so a signed build stays signed); builds it if missing.
[ -d dist/Applarchy.app ] || scripts/build.sh
STAGE=$(mktemp -d)
cp -R dist/Applarchy.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/Applarchy-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Applarchy $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "→ $DMG ($(du -h "$DMG" | cut -f1))"
