#!/bin/bash
# The next release version, from what was merged since the latest release. Used by
# .github/workflows/release.yml; run it locally to see what main would release as.
#
# Each pull request merged since the latest v* tag counts by its labels (the highest wins):
#   release: major, breaking                 → major  (2.4 → 3.0)
#   release: minor, enhancement, feature     → minor  (2.4 → 2.5)
#   release: patch, bug, or no label         → patch  (2.4 → 2.4.1)
#   release: skip                            → nothing on its own (CI, docs)
# A commit pushed to main without a pull request counts by its message: "BREAKING" → major,
# "[skip release]" → nothing, anything else → patch.
# The VERSION file is a floor: when it's ahead of the latest release it's released as it is,
# whatever the labels (to set a version by hand, e.g. 3.0).
#
# Env: BUMP=patch|minor|major overrides the labels; PR=<number> is a dry run for an open pull
# request (what main would release as with it merged). In Actions, GH_TOKEN for gh, and the
# results go to $GITHUB_OUTPUT (release, version, bump) and $GITHUB_STEP_SUMMARY.
set -euo pipefail
cd "$(dirname "$0")/.."
REPO=${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}
FLOOR=$(tr -d '[:space:]' < "${VERSION_FILE:-VERSION}")

norm() { local a b c; IFS=. read -r a b c <<< "$1"; echo "${a:-0}.${b:-0}.${c:-0}"; }
# "2.4" < "2.4.1" < "2.5", numerically per component, as Updates.isNewer compares them in the app.
newer() {
  local x y; x=$(norm "$1"); y=$(norm "$2")
  [ "$x" != "$y" ] && [ "$(printf '%s\n%s\n' "$x" "$y" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)" = "$x" ]
}
show() { local a b c; IFS=. read -r a b c <<< "$(norm "$1")"; if [ "$c" = 0 ]; then echo "$a.$b"; else echo "$a.$b.$c"; fi; }
NAMES=(skip patch minor major)

# Labels (one per line) → 0 skip, 1 patch, 2 minor, 3 major.
level() {
  local l=1 skip=0 name
  while read -r name; do
    case "$(tr '[:upper:]' '[:lower:]' <<< "$name")" in
      "release: major" | breaking) l=3 ;;
      "release: minor" | enhancement | feature) [ $l -lt 2 ] && l=2 ;;
      "release: skip") skip=1 ;;
    esac
  done
  if [ $skip = 1 ] && [ $l = 1 ]; then echo 0; else echo $l; fi
}

git fetch -q --tags origin 2>/dev/null || true
LAST=$(git tag -l 'v[0-9]*' | sed 's/^v//' | while read -r v; do echo "$(norm "$v") $v"; done \
  | sort -t. -k1,1n -k2,2n -k3,3n | tail -1 | cut -d' ' -f2)
HEAD_REF=HEAD
[ -n "${PR:-}" ] && HEAD_REF=origin/main
RANGE=${LAST:+v$LAST..}$HEAD_REF

# What's in the release: merged pull requests by number, and commits pushed without one.
PRS=""           # bash 3.2 (macOS): no associative arrays
DIRECT=()
for sha in $(git rev-list "$RANGE"); do
  found=$(gh api "repos/$REPO/commits/$sha/pulls" --jq '.[] | select(.merged_at != null) | .number')
  if [ -n "$found" ]; then PRS="$PRS $found"; else DIRECT+=("$sha"); fi
done
[ -n "${PR:-}" ] && PRS="$PRS $PR"

BUMPLVL=0
ROWS=()
for n in $(printf '%s\n' $PRS | sort -nu); do
  title=$(gh pr view "$n" --repo "$REPO" --json title -q .title)
  labels=$(gh pr view "$n" --repo "$REPO" --json labels -q '.labels[].name')
  l=$(level <<< "$labels")
  [ $l -gt $BUMPLVL ] && BUMPLVL=$l
  ROWS+=("| #$n | ${title//|/\\|} | ${labels:+${labels//$'\n'/, }}${labels:-(no label: patch)} | ${NAMES[$l]} |")
done
for sha in ${DIRECT[@]+"${DIRECT[@]}"}; do
  msg=$(git log -1 --format=%s%n%b "$sha")
  case "$msg" in *"[skip release]"*) l=0 ;; *BREAKING*) l=3 ;; *) l=1 ;; esac
  [ $l -gt $BUMPLVL ] && BUMPLVL=$l
  ROWS+=("| ${sha:0:7} | $(head -1 <<< "$msg") | (pushed without a pull request) | ${NAMES[$l]} |")
done

RELEASE=true
REASON=""
if [ -z "${PR:-}" ] && [ -n "$(git tag --points-at HEAD -l 'v[0-9]*')" ]; then
  RELEASE=false; REASON="this commit is already released"
elif [ "${BUMP:-auto}" != auto ]; then
  for i in 1 2 3; do [ "${NAMES[$i]}" = "$BUMP" ] && BUMPLVL=$i; done
  REASON="bump set by hand"
elif [ ${#ROWS[@]} = 0 ]; then
  RELEASE=false; REASON="nothing merged since v$LAST"
elif [ $BUMPLVL = 0 ]; then
  RELEASE=false; REASON="everything since v$LAST is labelled 'release: skip'"
fi

VERSION=""
if [ $RELEASE = true ]; then
  if [ -z "$LAST" ] || newer "$FLOOR" "$LAST"; then
    VERSION=$(show "$FLOOR"); REASON="${REASON:+$REASON; }the VERSION file ($FLOOR) is ahead of the latest release"
  else
    IFS=. read -r MA MI PA <<< "$(norm "$LAST")"
    case $BUMPLVL in
      3) VERSION="$((MA + 1)).0" ;;
      2) VERSION="$MA.$((MI + 1))" ;;
      *) VERSION=$(show "$MA.$MI.$((PA + 1))") ;;
    esac
  fi
  if git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null; then
    echo "::error::tag v$VERSION already exists" >&2; exit 1
  fi
fi

if [ $RELEASE = true ]; then
  HEADLINE="Releases as **$VERSION** (${NAMES[$BUMPLVL]} from ${LAST:-nothing}${REASON:+; $REASON})"
else
  HEADLINE="No release: $REASON"
fi
[ -n "${PR:-}" ] && HEADLINE="If #$PR were merged now: $HEADLINE"
SUMMARY=$(printf '%s\n\n| | Change | Labels | Bump |\n|---|---|---|---|\n' "$HEADLINE"; printf '%s\n' ${ROWS[@]+"${ROWS[@]}"})
echo "$SUMMARY"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  { echo "release=$RELEASE"; echo "version=$VERSION"; echo "bump=${NAMES[$BUMPLVL]}"; } >> "$GITHUB_OUTPUT"
fi
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then echo "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"; fi
