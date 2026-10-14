# engine — ttfx 0.5.0, embedded

This is [ttfx](https://github.com/omacom/ttfx) v0.5.0 (MIT), the Rust port of
[TerminalTextEffects](https://github.com/ChrisBuilds/terminaltexteffects) that Omarchy's
screensaver uses, vendored with one addition so it can run inside a macOS screensaver
and app instead of a terminal:

- `src/saver_ffi.rs` — a small C interface (`ttfx_saver_new_named`, `ttfx_saver_next`, …)
  that builds an effect on a fixed canvas and hands out frames one at a time.
- `src/fx/run.rs` — `step()`, which advances one frame for an embedder.
- `Cargo.toml` — also builds a `staticlib`.

Everything else is upstream, unchanged. See `LICENSE` and `NOTICE` for the original
copyright, and `README.upstream.md` for upstream's README.
