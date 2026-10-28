#!/bin/bash
# Sign Applarchy with a Developer ID, notarize the DMG with Apple and staple the
# ticket, so it opens without the "Open Anyway" step. Needs a paid Apple Developer
# account. One-time setup:
#
#   xcrun notarytool store-credentials applarchy --apple-id you@example.com --team-id TEAMID
#
# Then:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (TEAMID)" NOTARY_PROFILE=applarchy scripts/sign-and-notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."
: "${DEVELOPER_ID:?set DEVELOPER_ID to your 'Developer ID Application: …' signing identity}"
: "${NOTARY_PROFILE:?set NOTARY_PROFILE to a notarytool keychain profile (see above)}"
export APPLARCHY_FLAVOR="${APPLARCHY_FLAVOR:-release}"     # signing is for releases
source scripts/flavor.sh
APP="dist/$APP_NAME.app"
DMG="dist/${APP_NAME// /-}-$VERSION.dmg"

scripts/build.sh
# Inside out: the bundled screensaver first, then the app (hardened runtime, secure timestamp).
codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$APP/Contents/Resources/$APP_NAME.saver"
codesign --force --timestamp --options runtime --sign "$DEVELOPER_ID" "$APP"
codesign --verify --strict --verbose=2 "$APP"

scripts/package-dmg.sh
codesign --force --timestamp --sign "$DEVELOPER_ID" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"
echo "→ $DMG (signed and notarized)"
