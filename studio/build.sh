#!/bin/bash
# Build "Applarchy.app": the shared effect view (renamed) + the app UI,
# with the Applarchy screensaver bundled inside as the template it installs.
set -euo pipefail
cd "$(dirname "$0")"
VERSION=$(cat ../VERSION)
S=../saver
"$S/build.sh" >/dev/null
APP="build/Applarchy.app/Contents"
rm -rf build && mkdir -p "$APP/MacOS" "$APP/Resources" build/src
sed "s/ApplarchySaverView/StudioEffectView/g" $S/ApplarchySaverView.swift > build/src/StudioEffectView.swift
cp $S/PixelClock.swift $S/LogoArt.swift *.swift build/src/
swiftc -O -module-name Applarchy -target arm64-apple-macos13 \
  -import-objc-header $S/ttfx.h build/src/*.swift ../engine/target/release/libttfx.a \
  -framework ScreenSaver -framework AppKit -framework SwiftUI -framework CoreText \
  -o "$APP/MacOS/Applarchy" 2>&1 | { grep -v '^ld: warning' || true; }
rm -rf build/src
cp AppIcon.icns "$APP/Resources/"
cp -R "$S/build/Applarchy.saver" "$APP/Resources/"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Applarchy</string>
  <key>CFBundleIdentifier</key><string>com.applarchy.app</string>
  <key>CFBundleName</key><string>Applarchy</string>
  <key>CFBundleDisplayName</key><string>Applarchy</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Effects: TerminalTextEffects by ChrisBuilds, ttfx port by omacom.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP/Resources/Applarchy.saver"
codesign --force --sign - "build/Applarchy.app"
echo "built $(pwd)/build/Applarchy.app"
