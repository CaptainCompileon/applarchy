#include <stddef.h>
#include <stdint.h>
typedef struct Saver Saver;
Saver *ttfx_saver_new(const char *text, int width, int height, uint64_t seed);
const uint8_t *ttfx_saver_next(Saver *saver, size_t *len);
const uint8_t *ttfx_saver_effect_name(const Saver *saver, size_t *len);
void ttfx_saver_free(Saver *saver);
Saver *ttfx_saver_new_named(const char *text, int width, int height, uint64_t seed, const char *name);
