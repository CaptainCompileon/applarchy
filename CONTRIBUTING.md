# Contributing

How to build, test and release Applarchy, and how we work. How it fits together is in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md); the README covers users.

## Build

You need the Xcode Command Line Tools and Rust:

```bash
xcode-select --install
brew install rustup && rustup default stable      # or https://rustup.rs
rustup target add x86_64-apple-darwin             # for universal (Apple Silicon + Intel) builds
```

```bash
scripts/dev.sh                                     # build, install ~/Applications/Applarchy DEV.app, open it
APPLARCHY_FLAVOR=release scripts/build.sh          # → dist/Applarchy.app
APPLARCHY_FLAVOR=release scripts/package-dmg.sh    # → dist/Applarchy-<version>.dmg
```

- **DEV and release flavors** (`scripts/flavor.sh`): local builds are *Applarchy DEV*, with their
  own app ID (`com.applarchy.app.dev`), settings, login item, screensaver (`Applarchy DEV.saver`,
  class `ApplarchyDevSaverView`), Smooth Mode handoff names and lock-screen backup folder, so they
  run next to an installed Applarchy without touching it. DEV builds skip the update check and
  the migration from older apps. Only the release workflow builds plain *Applarchy*.
- Without the x86_64 target the build is Apple Silicon only; `ARM64_ONLY=1` forces that.
- The version comes from `VERSION`, or `APPLARCHY_VERSION` (the release workflow stamps it).
- After installing a new screensaver build, the running `legacyScreenSaver` keeps the old code:
  the app restarts it when it updates the screensaver; by hand, `killall legacyScreenSaver`.

### Troubleshooting

- **`unknown architecture arm64e.x1` in `libSystem.tbd`**: a newer or beta SDK sits next to an
  older linker, and `xcrun` picks the newest SDK. Pin one, e.g.
  `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk scripts/build.sh`.
- **A failed build exits 0**: don't pipe it through `tail` or `grep` without `set -o pipefail`.
- **The screensaver build's errors are hidden**: `studio/build.sh` silences `saver/build.sh`; run
  `saver/build.sh` on its own to see them.
- **`source scripts/engine.sh` from zsh fails**: the scripts are bash (`BASH_SOURCE`).

## Test

- `cd engine && cargo test --release`: the engine's unit tests.
- Pull requests run `.github/workflows/build.yml` (the universal DMG, as a downloadable artifact)
  and a dry run of the release (what merging would release as).
- UI changes: render the window in both appearances with the snapshot hooks below and look at them.
- Anything touching the screensaver, Smooth Mode or the lock screen needs a run on a real Mac:
  `LockScreen` edits macOS's wallpaper store, so try it on the DEV build, which keeps its own backup.

### Debugging hooks

| Hook | What it does |
|---|---|
| `Applarchy --window-snapshot out.png` | The real window, off-screen, captured after a delay (README images, UI checks) |
| `OMARCHY_SNAPSHOT="effects;logo;clock;focus;tutorial;theme"` | Its selection, e.g. `";apple;1;;0;nord"` |
| `OMARCHY_SNAPSHOT_APPEARANCE=light` | Light appearance (default Dark) |
| `OMARCHY_SNAPSHOT_MODE=smooth` | The mode picker's selection (default `custom`; kept apart from real settings) |
| `OMARCHY_SNAPSHOT_DELAY=5` | Seconds before the capture |
| `OMARCHY_SNAPSHOT_EDITOR=1` | Open the custom-logo editor |
| `OMARCHY_SNAPSHOT_PAGE=2` | Tutorial page |
| `OMARCHY_PREVIEW_DIRECT=1` | Draw the preview directly (for window captures) |
| `Applarchy --snapshot prefix` | `ImageRenderer` PNGs of the main view and tutorial steps |
| `OMARCHY_EFFECT=matrix` | Force one effect in any view |
| `log stream --predicate 'subsystem BEGINSWITH "com.applarchy"'` | Screensaver instances (`start`, `plays`, `announced … settling`), the wallpaper (`pause`, `screensaver stopped`, per-screen `run` / `stop (reason)`, `handoff … at frame N`) |

Use `/usr/bin/log` in zsh: a bare `log` is a zsh built-in.

## Release

Every push to `main` that changes the app is released automatically (`.github/workflows/release.yml`),
versioned from the merged pull requests' labels. The rules, including when a change is major, are in
the README's "Releases". In short: label each pull request `release: major`, `release: minor`,
`release: patch` or `release: skip`. `scripts/next-version.sh` prints what `main` would release as.

## Working with Linear and GitHub

- Every change starts from a Linear issue, with one type label (Bug, Feature, Improvement,
  Documentation) and one area label.
- One pull request per change, against `main` (not stacked on another branch: a stacked pull
  request merges into its base branch, not `main`).
- Write `Fixes APP-n` in the pull request: Linear links it and closes the issue when it merges.
  One pull request can close several: `Fixes APP-5, APP-6`.
- Give it a `release:` label, and say in the description how it was tested and what wasn't.
