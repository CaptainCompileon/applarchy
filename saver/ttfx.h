// The ttfx engine's C interface (engine/src/saver_ffi.rs), for the screensaver view.
// All functions are called on one thread; a Saver is not thread-safe.
#include <stddef.h>
#include <stdint.h>

/// One effect playing over some text on a fixed canvas.
typedef struct Saver Saver;

/// A random effect over `text` (UTF-8) on a `width` × `height` cell canvas, deterministic for
/// `seed`. Null on failure.
Saver *ttfx_saver_new(const char *text, int width, int height, uint64_t seed);

/// The next frame: ANSI text (truecolor SGR, UTF-8), one row per line, top first; its length in
/// `len`. Valid until the next call on this saver. Null when the effect has finished, leaving the
/// last frame and `len` as they were.
const uint8_t *ttfx_saver_next(Saver *saver, size_t *len);

/// The effect's name (not NUL-terminated); its length in `len`.
const uint8_t *ttfx_saver_effect_name(const Saver *saver, size_t *len);

/// Releases a saver from ttfx_saver_new or ttfx_saver_new_named. Null is fine.
void ttfx_saver_free(Saver *saver);

/// A named effect: `name` is a command, `[--global value…] effect [--option value…]`, e.g.
/// "--terminal-background-color 1a1b26 thunderstorm --storm-time 600". Null if it doesn't
/// parse or can't be built (callers fall back to ttfx_saver_new).
Saver *ttfx_saver_new_named(const char *text, int width, int height, uint64_t seed, const char *name);
