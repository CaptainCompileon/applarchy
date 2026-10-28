#!/bin/bash
# Build "Applarchy.app" ("Applarchy DEV.app" for a dev build, see scripts/flavor.sh):
# the shared effect view (renamed) + the app UI, with the screensaver bundled inside
# as the template it installs.
set -euo pipefail
cd "$(dirname "$0")"
source ../scripts/flavor.sh
S=../saver
"$S/build.sh" >/dev/null
source ../scripts/engine.sh
BUNDLE="build/$APP_NAME.app"
APP="$BUNDLE/Contents"
rm -rf build && mkdir -p "$APP/MacOS" "$APP/Resources" build/src
sed "s/ApplarchySaverView/StudioEffectView/g" $S/ApplarchySaverView.swift > build/src/StudioEffectView.swift
cp $S/PixelClock.swift $S/LogoArt.swift $S/Themes.swift *.swift build/src/
for arch in $ARCHS; do
  swiftc -O -module-name Applarchy -target "$arch-apple-macos13" \
    -import-objc-header $S/ttfx.h build/src/*.swift "$ENGINE_LIB" \
    -framework ScreenSaver -framework AppKit -framework SwiftUI -framework CoreText \
    -o "build/Applarchy-$arch" 2>&1 | { grep -v '^ld: warning' || true; }
done
lipo -create build/Applarchy-* -output "$APP/MacOS/$APP_EXEC"
rm -f build/Applarchy-*
rm -rf build/src
cp AppIcon.icns fonts/DepartureMono-Regular.otf fonts/DepartureMono-LICENSE.txt "$APP/Resources/"
cp -R "$S/build/$APP_NAME.saver" "$APP/Resources/"
cat > "$APP/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>$APP_EXEC</string>
  <key>CFBundleIdentifier</key><string>$APP_ID</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>ApplarchyFlavor</key><string>$FLAVOR</string>
  <key>ApplarchyCommit</key><string>$COMMIT</string>
  <key>ApplarchySaverBundle</key><string>$APP_NAME.saver</string>
  <key>ApplarchyHandoffID</key><string>$HANDOFF_ID</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
  <key>LSUIElement</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHumanReadableCopyright</key><string>MIT License. Effects: TerminalTextEffects by ChrisBuilds, ttfx port by omacom.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$APP/Resources/$APP_NAME.saver"
codesign --force --sign - "$BUNDLE"
echo "built $(pwd)/$BUNDLE"
