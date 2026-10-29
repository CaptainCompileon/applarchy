# Changelog

Every push to `main` that changes the app is released automatically (see "Releases" in the
README). Each release's notes on [GitHub Releases](https://github.com/CaptainCompileon/applarchy/releases)
list its pull requests, grouped by their `release:` label (`.github/release.yml`). This file keeps
the history in one place; the issue IDs are [Linear](https://linear.app/applarchy)'s.

## 2.2.1 (2026-10-29)

### Fixed
- Smooth Mode: the desktop glides the logo to the centre after the screensaver even when its
  effect had already finished (APP-31, #11).

## 2.2 (2026-10-29)

The first release since 2.0; 2.1 was never published.

### New
- **Smooth Mode**, now the default: one look for the screensaver, the lock screen and the desktop.
  When you come back, the desktop carries on the screensaver's animation from the same frame,
  settles gently and glides the logo to the centre. Locking plays the animation on the lock screen;
  Turn Off restores the previous wallpaper and lock screen (APP-20, #2; APP-29, #10).
- **All screens in step**: every display plays the same effect from the same moment, and the next
  effect starts on all of them together (APP-24, #9).
- **120 FPS and Auto** frame rates; Auto (and the screensaver) follow each display's refresh rate,
  up to 120 (APP-22, #5; APP-26, #8).
- The layout fits any screen, ultrawide and portrait included (APP-21, #4).
- Local builds are "Applarchy DEV", installable next to the released app (#3).
- Releases are made automatically from `main`, versioned by the pull requests' labels (APP-32, #12).

### Fixed
- Smooth Mode's desktop no longer stays on a static logo after the screensaver, after a display
  wake or on battery (APP-27, #9).
- Effects keep their pace under load, so a busy screen no longer falls behind (#9).
- Light mode: the window follows the system appearance (APP-5, APP-11, #1).
- Each effect's final frame is drawn (APP-6); the wallpaper no longer leaks an observer per
  rebuild (APP-7) (#1).
- DEV and released builds keep their Smooth Mode handoff and lock-screen backup apart (#6).

## 2.0 (2026-10-14)

### New
- Themes: Omarchy's colours or Tokyo Night, Catppuccin, Gruvbox, Nord, Everforest, Kanagawa,
  Rosé Pine, Matte Black. A theme recolours each effect, the background and the clock.
- Custom logo from any picture or pasted text art, editable, with a live preview.
- Clock: 12/24-hour or system, date on or off, small or large.
- Wallpaper at 30 or 15 fps; pause on battery or in Low Power Mode.
- Reduce Motion: only the calm effects play while it's on.
- Update notices from GitHub releases, in the window and the menu bar.
- Universal build (Apple Silicon + Intel), and signed and notarized builds by script.

## 1.2 (2026-10-14)

### Changed
- Every control is drawn in the app's pixel style: square checkboxes, a custom effect list, a thin
  scroll bar, terminal-style status lines, a square tutorial card, a pixel menu-bar icon.

## 1.1 (2026-10-14)

### Changed
- One pixel typeface everywhere: Departure Mono, at sizes that land every stem on whole pixels.

## 1.0 (2026-10-14)

- Omarchy's terminal-art screensaver for macOS: all 37 TerminalTextEffects effects over the Apple
  logo, as a screensaver with a pixel clock or as a live wallpaper, set up from a small app with a
  live preview and a first-run tutorial.
