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
open "$DEST"
echo "→ $DEST"
