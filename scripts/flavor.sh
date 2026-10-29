# Sourced by the build scripts: which Applarchy to build. APPLARCHY_FLAVOR=release
# (the release workflow) builds "Applarchy"; anything else, the default, builds
# "Applarchy DEV", which has its own app ID, settings, login item and screensaver,
# so it installs and runs next to a released Applarchy.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The release workflow stamps the version it worked out (scripts/next-version.sh);
# otherwise the VERSION file's.
VERSION=${APPLARCHY_VERSION:-$(cat "$ROOT/VERSION")}
COMMIT=$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)
if [ "${APPLARCHY_FLAVOR:-dev}" = release ]; then
  FLAVOR=release
  APP_NAME="Applarchy"
  APP_EXEC=Applarchy
  APP_ID=com.applarchy.app
  SAVER_ID=com.applarchy.screensaver
  SAVER_CLASS=ApplarchySaverView     # also its Objective-C name: unique per installed screensaver
  HANDOFF_ID=com.applarchy.handoff   # Smooth Mode's notification and pasteboards (app and screensaver)
else
  FLAVOR=dev
  APP_NAME="Applarchy DEV"
  APP_EXEC=ApplarchyDEV
  APP_ID=com.applarchy.app.dev
  SAVER_ID=com.applarchy.screensaver.dev
  SAVER_CLASS=ApplarchyDevSaverView
  HANDOFF_ID=com.applarchy.handoff.dev
fi
