#!/bin/bash
# Install (or update) Applarchy from the latest GitHub release, without the "Open Anyway"
# step: curl doesn't mark what it downloads as quarantined, so Gatekeeper doesn't stop it.
#
#   curl -fsSL https://raw.githubusercontent.com/CaptainCompileon/applarchy/main/scripts/install.sh | bash
#
# APPLARCHY_VERSION=2.7.2 installs that release instead; APPLARCHY_DIR another folder
# than /Applications.
set -euo pipefail

REPO=CaptainCompileon/applarchy
APP=Applarchy.app

# All in a function, called on the last line: a download cut short runs nothing.
main() {
  [ "$(uname -s)" = Darwin ] || fail "Applarchy is a macOS app"
  local dir=${APPLARCHY_DIR:-/Applications}
  local release=latest
  [ -z "${APPLARCHY_VERSION:-}" ] || release="tags/v${APPLARCHY_VERSION#v}"
  [ -d "$dir" ] && [ -w "$dir" ] || fail "can't write to $dir (set APPLARCHY_DIR to a folder you can, like ~/Applications)"

  local url
  url=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/$release" \
    | grep -o '"browser_download_url": *"[^"]*\.dmg"' | head -1 | cut -d'"' -f4) || true
  [ -n "$url" ] || fail "no Applarchy DMG found in the $release release"

  TMP=$(mktemp -d)
  trap cleanup EXIT
  echo "→ Downloading ${url##*/}"
  curl -fL --progress-bar "$url" -o "$TMP/applarchy.dmg"
  hdiutil attach "$TMP/applarchy.dmg" -nobrowse -readonly -mountpoint "$TMP/mnt" >/dev/null
  [ -d "$TMP/mnt/$APP" ] || fail "the DMG has no $APP"

  # Replacing a running app pulls the files out from under it: quit the copy we replace first.
  local dest="$dir/$APP"
  if pgrep -qf "$dest/Contents/MacOS/"; then
    echo "→ Quitting the running Applarchy"
    osascript -e 'quit app id "com.applarchy.app"' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -qf "$dest/Contents/MacOS/" || break; sleep 0.5; done
  fi

  echo "→ Installing to $dest"
  rm -rf "$dest"
  ditto "$TMP/mnt/$APP" "$dest"
  xattr -dr com.apple.quarantine "$dest" 2>/dev/null || true   # in case it came through one that sets it
  echo "✓ Applarchy $(defaults read "$dest/Contents/Info" CFBundleShortVersionString) installed. Open it from $dir."
}

cleanup() {
  [ ! -d "$TMP/mnt" ] || hdiutil detach "$TMP/mnt" -quiet || true
  rm -rf "$TMP"
}

fail() { echo "error: $*" >&2; exit 1; }

main "$@"
