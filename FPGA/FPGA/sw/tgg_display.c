#include "tgg_display.h"
#include "xil_io.h"
#ifndef TGG_HOST_TEST
#include "xparameters.h"
#endif
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#ifndef TGG_LCD_BASEADDR
#if defined(XPAR_TGG_LCD_0_S_AXI_BASEADDR)
#define TGG_LCD_BASEADDR XPAR_TGG_LCD_0_S_AXI_BASEADDR
#elif defined(XPAR_TGG_LCD_0_BASEADDR)
#define TGG_LCD_BASEADDR XPAR_TGG_LCD_0_BASEADDR
#else
/* This is assigned explicitly by create_lcd_project.tcl. */
#define TGG_LCD_BASEADDR 0x43C10000u
#endif
#endif
#define STATUS 0x8000u
#define COMMIT 0x8004u
#define CONTROL 0x8008u
#define PANEL_ID 0x800cu
#define PAGE_BYTES 0x4000u
#define LIMIT 2000000u
static char text[2048];
static unsigned enabled;
static uint32_t rd(unsigned a) { return Xil_In32(TGG_LCD_BASEADDR+a); }
static void wr(unsigned a,unsigned v) { Xil_Out32(TGG_LCD_BASEADDR+a,v); }
static void barrier(void) {
#if defined(__arm__) || defined(__aarch64__)
    __asm__ volatile("dmb sy" ::: "memory");
#elif defined(__GNUC__)
    __sync_synchronize();
#endif
}
static int idle(void) {
    unsigned n;
    for(n=0;n<LIMIT;++n) if (!(rd(STATUS)&2u)) return 1;
    return 0;
}
/* No floating-point printf support is needed in the standalone BSP. */
static void fixed(char *out, size_t cap, double v, unsigned dp) {
    unsigned long long scale=1, q;
    unsigned i;
    if (!isfinite(v)) { snprintf(out,cap,"INVALID");return; }
    for(i=0;i<dp;++i) scale*=10u;
    if (fabs(v)>1e9) { snprintf(out,cap,"RANGE");return; }
    q=(unsigned long long)(fabs(v)*(double)scale+0.5);
    if(dp) snprintf(out,cap,"%s%llu.%0*llu",v<0&&q?"-":"",q/scale,(int)dp,q%scale);
    else snprintf(out,cap,"%s%llu",v<0&&q?"-":"",q);
}
static void line(unsigned row,const char *s) {
    size_t n=strlen(s);if(n>60)n=60;
    memcpy(text+row*64,s,n);
}
static void value(unsigned row,const char *label,double v,unsigned dp,const char *unit) {
    char n[40],s[80];fixed(n,sizeof(n),v,dp);
    snprintf(s,sizeof(s),"%s %s %s",label,n,unit);line(row,s);
}
static unsigned ycode(double v,double lo,double hi) {
    double y;
    if (!isfinite(v)||!isfinite(lo)||!isfinite(hi)||hi<=lo) return 48;
    y=95.0*(hi-v)/(hi-lo);if(y<0)y=0;if(y>95)y=95;
    return (unsigned)(y+0.5);
}
int tgg_display_init(void) {
    unsigned n,id,p,i;
    enabled=0;
    for(n=0;n<LIMIT;++n) if((rd(PANEL_ID)&0x200u))break;
    id=rd(PANEL_ID);if((id&0x300u)!=0x300u)return 0;
    if((id&7u)!=0 && (id&7u)!=1 && (id&7u)!=2 && (id&7u)!=4 && (id&7u)!=5)return 0;
    wr(CONTROL,2); /* Backlight off; clear errors. */
    if(!idle())return 0;
    for(p=0;p<2;++p) {
        for(i=0;i<2048;++i)wr(p*PAGE_BYTES+4*i,' ');
        for(i=2048;i<2816;++i)wr(p*PAGE_BYTES+4*i,95);
    }
    /* Backlight stays off until a complete first result has been committed. */
    enabled=1;return 1;
}
int tgg_display_update(const uint16_t raw[TGG_N],const tgg_result_t *r,
                       unsigned frame_id,unsigned bank,unsigned overflow,
                       unsigned gap_events,double vmax) {
    unsigned page,base,i,k,span=256,raw_min=4095,raw_max=0;
    double lo=1e30,hi=-1e30,fft_max=0;
    char s[100],a[32],b[32];
    if(!enabled||!idle())return 0;
    page=(rd(STATUS)&1u)^1u;base=page*PAGE_BYTES;
    memset(text,' ',sizeof(text));
    snprintf(s,sizeof(s),"TGG MD0700R 800X480 FRAME %u BANK %u",frame_id,bank);line(0,s);
    snprintf(s,sizeof(s),"FS 10000 HZ  N 4096  GAP EVENTS %u",gap_events);line(1,s);
    snprintf(s,sizeof(s),"CAPTURE %s  ADC 0..1V  ANGLE RAD",overflow?"PAUSED/GAP":"RUN");line(2,s);
    value(3,"FFT PEAK F",r->peak_frequency,4,"HZ");
    value(4,"FFT PEAK A",r->peak_amplitude,8,"RAD");
    value(5,"FFT INTERP F",r->refined_frequency,4,"HZ");
    value(6,"FFT INTERP A",r->refined_amplitude,8,"RAD");
    value(7,"SINE FIT F",r->fitted_frequency,4,"HZ");
    value(8,"SINE FIT A",r->fitted_amplitude,8,"RAD");
    value(9,"PHASE",r->fitted_phase,8,"RAD");
    value(10,"OFFSET",r->fitted_offset,8,"RAD");
    value(11,"R SQUARED",r->r_squared,4,"");
    for(i=0;i<TGG_N;++i) {
        double t=tgg_theta_at(i);
        if(raw[i]<raw_min)raw_min=raw[i];
        if(raw[i]>raw_max)raw_max=raw[i];
        if(t<lo)lo=t;
        if(t>hi)hi=t;
    }
    if(hi-lo<1e-8){lo-=1e-4;hi+=1e-4;}
    fixed(a,sizeof(a),raw_min/4095.0,4);fixed(b,sizeof(b),raw_max/4095.0,4);
    snprintf(s,sizeof(s),"INPUT MIN %s MAX %s V",a,b);line(12,s);
    value(13,"EXPERIMENT VMAX",vmax,4,"V");
    fixed(a,sizeof(a),lo,5);fixed(b,sizeof(b),hi,5);
    snprintf(s,sizeof(s),"THETA Y %s .. %s RAD",a,b);line(14,s);
    if(isfinite(r->fitted_frequency)&&r->fitted_frequency>0) {
        double want=4*TGG_FS/r->fitted_frequency;
        span=want>TGG_N?TGG_N:(want<32?32:(unsigned)want);
    }
    value(15,"TIME X 0 TO",(span-1)/TGG_FS,5,"S");
    for(k=0;k<=TGG_N/2;++k)if(tgg_spectrum_at(k)>fft_max)fft_max=tgg_spectrum_at(k);
    value(16,"FFT Y 0 TO",fft_max,6,"RAD");
    line(17,"THETA: GREEN MEASURED / YELLOW FIT");
    line(18,"FFT: CYAN  X 0..5000 HZ (BIN MAX)");
    line(19,"AUTO SCALE  THETA=ASIN(SQRT(V/VMAX))");
    for(i=0;i<2048;++i)wr(base+4*i,(unsigned char)text[i]);
    for(i=0;i<256;++i) {
        double at=(double)i*(span-1)/255.0;
        unsigned j=(unsigned)at;double f=at-j;
        double measured=tgg_theta_at(j)*(1-f)+tgg_theta_at(j+1<TGG_N?j+1:j)*f;
        double fit=r->fitted_offset+r->fitted_amplitude*sin(6.283185307179586*r->fitted_frequency*at/TGG_FS+r->fitted_phase);
        unsigned ka=i*(TGG_N/2+1)/256,kb=(i+1)*(TGG_N/2+1)/256;
        double peak=0;
        for(k=ka;k<kb;++k)if(tgg_spectrum_at(k)>peak)peak=tgg_spectrum_at(k);
        wr(base+4*(2048+i),ycode(measured,lo,hi));
        wr(base+4*(2304+i),ycode(fit,lo,hi));
        wr(base+4*(2560+i),ycode(peak,0,fft_max));
    }
    barrier();wr(COMMIT,2u|page);
    if(!idle())return 0;
    wr(CONTROL,1);return 1;
}
