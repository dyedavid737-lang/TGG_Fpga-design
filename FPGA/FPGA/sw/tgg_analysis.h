#ifndef TGG_ANALYSIS_H
#define TGG_ANALYSIS_H

#include <stdint.h>

// 一帧固定采集 4096 点。10 kHz 采样时，帧时长为 409.6 ms。
#define TGG_N   4096u
#define TGG_FS  10000.0

// tgg_process_frame() 计算出的结果。频率单位是 Hz，其余角度/振幅单位是 rad。
typedef struct {
    double peak_frequency;
    double peak_amplitude;
    double refined_frequency;
    double refined_amplitude;
    double fitted_frequency;
    double fitted_amplitude;
    double fitted_phase;
    double fitted_offset;
    double r_squared;
} tgg_result_t;

void tgg_process_frame(const uint16_t raw[TGG_N], double vmax,
                       double min_frequency, double max_frequency,
                       tgg_result_t *result);
void tgg_print_result(const tgg_result_t *result);
/* Read-only data from the most recently processed frame, for LCD plots. */
double tgg_theta_at(unsigned index);
double tgg_spectrum_at(unsigned bin);

#endif
