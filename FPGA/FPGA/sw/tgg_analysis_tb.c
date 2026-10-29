// Host-side regression test for the ARM analysis routine.
// Build on a PC with:  cc tgg_analysis.c tgg_analysis_tb.c -lm -o tgg_tb
#include "tgg_analysis.h"
#include <assert.h>
#include <math.h>
#include <stdio.h>
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

int main(void)
{
    uint16_t raw[TGG_N];
    const double f0=123.45, vmax=1.0;
    unsigned i;
    for (i=0;i<TGG_N;++i) {
        const double th=0.55+0.12*sin(2.0*M_PI*f0*(double)i/TGG_FS);
        const double v=sin(th)*sin(th)*vmax;
        raw[i]=(uint16_t)lround(v*4095.0);
    }
    tgg_result_t r;
    tgg_process_frame(raw,vmax,10.0,1000.0,&r);
    printf("estimated %.6f Hz (expected %.6f Hz)\n",r.fitted_frequency,f0);
    assert(fabs(r.fitted_frequency-f0)<0.5);
    assert(r.r_squared>0.98);
    return 0;
}
