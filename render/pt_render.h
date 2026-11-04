#ifndef PT_RENDER_H
#define PT_RENDER_H
#include <CoreGraphics/CoreGraphics.h>
#include <stdint.h>
#include "../core/pt_term.h"

typedef struct pt_render pt_render;

/* regular/bold: TTF data (DejaVu Sans Mono). point_size: font size in points. */
pt_render *pt_render_new(const void *regular, size_t regular_len, const void *bold, size_t bold_len, double point_size);
void pt_render_free(pt_render *r);
/* Run the system's font search once on a background thread. On iOS 6 the first character that no font has takes
 * 1730 ms and 13.5 MB in that call (measured on the iPad mini, 2026-11-04: U+1F9EA); later ones take 22 ms.
 * Without this, that one call froze a draw on the main thread for 2.3 s in the first message of a Claude session. */
void pt_render_prewarm_font_search(pt_render *r);

/* Cell size in points (whole numbers, so cells line up on pixels at scale 1 and 2). */
void pt_render_cell_size(const pt_render *r, double *w, double *h);

/* 1 if the bundled regular font has a glyph, 2 if the renderer draws it as a shape, 0 otherwise. */
int pt_render_coverage(const pt_render *r, uint32_t codepoint);

/* Draw the rows that intersect the clip of ctx (all rows if there is no clip). ctx must have a top-left
 * origin (y down). bg = theme background. */
void pt_render_draw(pt_render *r, CGContextRef ctx, const pt_term *t, const uint8_t bg[3]);

#endif
