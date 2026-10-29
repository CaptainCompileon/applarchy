#!/bin/bash
# Build "Applarchy DEV", install it to ~/Applications and (re)open it. It runs next
# to a released Applarchy: its own app ID, settings, login item and screensaver
# ("Applarchy DEV" in Screen Saver settings). ARM64_ONLY=1 skips the Intel slice.
set -euo pipefail
cd "$(dirname "$0")/.."
export APPLARCHY_FLAVOR=dev
source scripts/flavor.sh
studio/build.sh
DEST="$HOME/Applications/$APP_NAME.app"
# Quit the running copy first (a quit, not a kill: its login item restarts a crashed app).
if osascript -e "application id \"$APP_ID\" is running" 2>/dev/null | grep -q true; then   # errors before the first install
  osascript -e "tell application id \"$APP_ID\" to quit"
  for _ in $(seq 50); do pgrep -f "$DEST/Contents/MacOS/" >/dev/null || break; sleep 0.1; done
fi
mkdir -p "$HOME/Applications"
rm -rf "${DEST:?}"
cp -R "studio/build/$APP_NAME.app" "$DEST"
# Other copies with this app ID (this build folder, other checkouts' old builds) let macOS
# launch stale code by ID, e.g. a 2.0 build on a wide screen: forget all but the installed one.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -dump Bundle 2>/dev/null \
  | awk -v id="$APP_ID" '/^path:/ { sub(/^path: +/, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); p = $0 } $1 == "identifier:" && $2 == id { print p }' \
  | sort -u | while read -r copy; do
  [ "$copy" = "$DEST" ] || "$LSREGISTER" -u "$copy" 2>/dev/null || true
done
"$LSREGISTER" -f "$DEST"
open "$DEST"
echo "→ $DEST"
