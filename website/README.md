# applarchy website

The one-page site for Applarchy. It runs the app's own effect engine (`../engine`, ttfx) in the
browser, compiled to WebAssembly, so every effect on the page is the real thing rather than a
recording.

```
index.html          the page: all content is static HTML
src/main.ts         wiring: hero, the app window, themes, logo pad, modes, reveals
src/screen.ts       ApplarchySaverView for the web: grid layout, ANSI parser, block drawing, clock
src/engine.ts       loads ttfx.wasm (with the few WASI calls it needs) and steps effects
src/logos.ts        half-block logos, as saver/LogoArt.swift makes them
src/data.ts         themes, effects and the clock font, ported from the Swift code
src/ttfx.wasm       the engine, built by scripts/build-wasm.sh (committed: Vercel has no Rust)
wasm/               the tiny crate that re-exports the engine's C API for wasm32-wasip1
```

## Develop

```bash
npm install
npm run dev
```

After changing the engine, rebuild the WebAssembly with `npm run wasm` (needs rustup).

## Deploy

Vercel, connected to the GitHub repository with `website` as the project's root directory
(framework: Vite, `vercel.json`). Every push to `main` deploys to production, and every pull
request gets a preview deployment. To deploy by hand, from the repository's root (not `website/`):

```bash
npx vercel --prod
```

## Performance notes

- Critical path is about 50 KB gzipped: HTML, CSS, JS and the Departure Mono woff2. The engine
  (≈340 KB with Brotli) loads after first paint, the first time a screen scrolls into view.
- A screen only runs while it's on screen and the tab is visible. The engine keeps Omarchy's
  120 fps pace and the page draws only the latest frame, repainting only the cells that changed.
- With Reduce Motion on, screens play only the calm effects (as the app does) and the page's
  own animations are off.
