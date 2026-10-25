#!/bin/bash
# Package dist/Applarchy.app as dist/Applarchy-<version>.dmg (drag to Applications);
# a dev build as dist/Applarchy-DEV-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/flavor.sh
# Uses dist/<name>.app as it is (so a signed build stays signed); builds it if missing.
[ -d "dist/$APP_NAME.app" ] || scripts/build.sh
STAGE=$(mktemp -d)
cp -R "dist/$APP_NAME.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
DMG="dist/${APP_NAME// /-}-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$DMG" >/dev/null
rm -rf "$STAGE"
echo "→ $DMG ($(du -h "$DMG" | cut -f1))"
