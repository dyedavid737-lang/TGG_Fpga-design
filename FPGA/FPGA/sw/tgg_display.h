#ifndef TGG_DISPLAY_H
#define TGG_DISPLAY_H
#include "tgg_analysis.h"
/* Returns 0 on timeout/unknown panel. Acquisition is allowed to continue. */
int tgg_display_init(void);
int tgg_display_update(const uint16_t raw[TGG_N], const tgg_result_t *r,
                       unsigned frame_id, unsigned bank, unsigned overflow,
                       unsigned gap_events, double vmax);
#endif
