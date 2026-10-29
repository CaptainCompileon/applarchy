# Architecture

```
engine/  (Rust)   ttfx effects ──► C API: saver_ffi.rs ──► libttfx.a (static, universal)
                                        │ ANSI frame bytes
saver/   (Swift)  ApplarchySaverView ◄──┘  parse → cells → pixels
                  + PixelClock, LogoArt, Themes
studio/  (Swift)  the app (SwiftUI); compiles saver/ in as StudioEffectView for the
                  preview and the wallpaper, and installs saver/ as the screensaver
```

## The C API (`saver/ttfx.h`)

- `ttfx_saver_new_named(text, w, h, seed, command)` builds one effect from a command string:
  global `--name value` pairs first, then the effect name and its options. Null if it can't be
  built; the view then falls back to `ttfx_saver_new`, which picks a random effect, so a bad option
  fails silently.
- `ttfx_saver_next(saver, &len)` returns one frame of ANSI text (truecolor SGR plus UTF-8), valid
  until the next call, or null when the effect has ended (the previous frame and `len` untouched).
- The engine is deterministic for a seed: the same command, seed and canvas give the same frames.
  Smooth Mode relies on it.
- Every saver must be released with `ttfx_saver_free`.

## Frame loop

- The engine runs at Omarchy's 120 frames a second. A view with a clock (the shared timeline's
  effect, or a handed-off one) catches the engine up each tick to `120 × seconds since the effect
  started` (faster while settling) and draws once, so a slow tick drops a drawn frame instead of
  slowing the effect. Previews carry the fraction over instead.
- **Shared timeline** (`ApplarchySaverView.Timeline`, one per process): every animating view, one per
  screen plus the earlier instances macOS keeps alive in the screensaver host, plays the same effect
  with the same seed from the same moment. A view starting late catches up. A screen that finishes
  first holds the logo until all have; then the next effect starts everywhere together. Every effect
  plays once, shuffled, before any repeats.
- Frame rates: the screensaver runs at its display's refresh rate (capped at 120, 60 if unknown);
  the wallpaper at the picker's rate (Auto is the same rule); the preview at 30.

## Rendering

- Each frame is parsed into cells (character, colours), and only the cells that changed are
  redrawn, padded for glyphs that reach outside their cell.
- Block elements (U+2580–259F), which the logo is made of, are exact rectangles, so it has no
  seams; other characters go through Core Text (Menlo).
- The wallpaper and the preview draw into an offscreen 8-bit bitmap (`bitmapScale`), shown as the
  layer's contents scaled up nearest-neighbour, far cheaper than a Retina wide-colour backing store.
- Logo placement: ttfx centres text in its canvas, so the view asks for a canvas `extra` rows taller
  than the screen to move the logo below the clock (`logoLayout()`). The layout scales with the
  tighter of the screen's width or height (`layoutScale`).
- Themes are data (`saver/Themes.swift`); `Theme.command(for:)` turns one into ttfx options.

## Smooth Mode

- **Announcements**: each screensaver view announces the effect it starts (command, seed, start
  time, screen size) through a distributed notification and a per-screen named pasteboard
  (`<handoff id>.<W>x<H>`; the ID is per flavor, from the Info.plist). With the shared timeline,
  every instance announces the same for its screen size.
- **Settling**: when the mouse moves (`com.apple.screensaver.willstop`) the screensaver plays the
  rest of the effect faster and speeding up (`settledFrames`), then holds the logo, and announces when
  settling began.
- **The desktop** (the wallpaper in hold mode) pauses on `didstart` and, when the screensaver stops
  (`willstop` + 0.25 s, `didstop`, or unlock after the lock screen), rebuilds the announced effect,
  fast-forwards to the matching frame and carries on, or shows its last frame. The screensaver's
  layout leaves room for a clock the desktop doesn't draw, so once the effect is over the logo glides
  to the centre.
- **Lock screen**: locking starts `ScreenSaverEngine`, so the lock screen plays the animation.
  `LockScreen` renders a still of the logo per display and sets it as the desktop picture, copies
  that entry into every Space and the system-default slots of macOS's wallpaper store
  (`~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`) and restarts
  `WallpaperAgent`. The store is backed up first; Turn Off restores it.

## Settings and storage

| What | Where | Notes |
|---|---|---|
| Window draft | `UserDefaults` `draft` (JSON `EffectConfig`) | saved on every change |
| Mode | `UserDefaults` `mode` (`smooth` / `custom`) | first value inferred from what's set up |
| Wallpaper | `UserDefaults` `wallpaper`, `wallpaperOptions` | restored at launch |
| Tutorial | `UserDefaults` `tutorialSeen` | |
| Screensaver | `<name>.saver/Contents/Resources/config.json` | read on every start; the app rewrites it in place and re-signs |
| Login item | `~/Library/LaunchAgents/<app id>.plist` | `--background`, only while a wallpaper is set |
| Lock screen | `~/Library/Application Support/<app name>/` | the wallpaper-store backup and the stills |

`config.json` keys are `EffectConfig`'s fields: `effects`, `logo` (`apple-small`, `apple` or
`custom`), `showClock`, `theme`, `hourCycle` (`auto`, `12` or `24`), `showDate`, `clockLarge`,
`customLogo` and `smoothTransition`. New keys must be decoded with `decodeIfPresent`, so settings
saved by older versions keep loading.
