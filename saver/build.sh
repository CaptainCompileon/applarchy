#!/bin/bash
# Build Applarchy.saver: the ttfx engine as a static lib + the Swift ScreenSaverView.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat ../VERSION)
source ../scripts/engine.sh
OUT=build/Applarchy.saver/Contents
rm -rf build && mkdir -p "$OUT/MacOS" "$OUT/Resources"
SLICES=$(mktemp -d)
for arch in $ARCHS; do
  swiftc -O -module-name ApplarchySaverView -target "$arch-apple-macos13" \
    -import-objc-header ttfx.h ApplarchySaverView.swift PixelClock.swift LogoArt.swift Themes.swift "$ENGINE_LIB" \
    -framework ScreenSaver -framework AppKit -framework CoreText \
    -Xlinker -bundle -o "$SLICES/$arch" 2>&1 | { grep -v '^ld: warning' || true; }
done
lipo -create "$SLICES"/* -output "$OUT/MacOS/ApplarchySaverView"
rm -rf "$SLICES"
cat > "$OUT/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>ApplarchySaverView</string>
  <key>CFBundleIdentifier</key><string>com.applarchy.screensaver</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Applarchy</string>
  <key>CFBundleDisplayName</key><string>Applarchy</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSPrincipalClass</key><string>ApplarchySaverView</string>
</dict>
</plist>
PLIST
codesign --force --sign - build/Applarchy.saver
echo "built $(pwd)/build/Applarchy.saver"
