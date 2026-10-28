#!/bin/bash
# Build Applarchy.saver (Applarchy DEV.saver for a dev build): the ttfx engine as a
# static lib + the Swift ScreenSaverView.
set -euo pipefail
cd "$(dirname "$0")"
source ../scripts/flavor.sh
source ../scripts/engine.sh
SAVER="build/$APP_NAME.saver"
OUT="$SAVER/Contents"
rm -rf build && mkdir -p "$OUT/MacOS" "$OUT/Resources"
# The view class is renamed per flavor: screensavers share one host process, where
# two bundles exporting the same Objective-C class would clash.
SRC=$(mktemp -d)
sed "s/ApplarchySaverView/$SAVER_CLASS/g" ApplarchySaverView.swift > "$SRC/$SAVER_CLASS.swift"
SLICES=$(mktemp -d)
for arch in $ARCHS; do
  swiftc -O -module-name "$SAVER_CLASS" -target "$arch-apple-macos13" \
    -import-objc-header ttfx.h "$SRC/$SAVER_CLASS.swift" PixelClock.swift LogoArt.swift Themes.swift "$ENGINE_LIB" \
    -framework ScreenSaver -framework AppKit -framework CoreText \
    -Xlinker -bundle -o "$SLICES/$arch" 2>&1 | { grep -v '^ld: warning' || true; }
done
lipo -create "$SLICES"/* -output "$OUT/MacOS/$SAVER_CLASS"
rm -rf "$SLICES" "$SRC"
cat > "$OUT/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>$SAVER_CLASS</string>
  <key>CFBundleIdentifier</key><string>$SAVER_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>$SAVER_CLASS</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$SAVER"
echo "built $(pwd)/$SAVER"
