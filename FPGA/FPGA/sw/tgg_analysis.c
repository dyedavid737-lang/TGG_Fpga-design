#include "tgg_analysis.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

/*
 * 这是 tgg_final2.py 的 ARM C 版本，保留相同的数学步骤：
 *
 *   12 位 ADC code -> 0..1 V -> asin(sqrt(V/Vmax)) -> 去平均值
 *   -> 4096 点 FFT -> 频率范围内找峰 -> 三点插值
 *   -> a*sin(wt)+b*cos(wt)+c 最小二乘拟合
 *
 * 这些数组是静态数组，不放在 ARM 的栈上，避免 4096 点数据导致栈溢出。
 */

static double theta[TGG_N];
static double fft_re[TGG_N];
static double fft_im[TGG_N];
static double amplitude[TGG_N/2 + 1];

double tgg_theta_at(unsigned index) { return index<TGG_N ? theta[index] : 0.0; }
double tgg_spectrum_at(unsigned bin) { return bin<=TGG_N/2 ? amplitude[bin] : 0.0; }

typedef struct {
    double mse, a, b, c;
} fit_t;

static void fft(double *re, double *im, unsigned n)
{
    unsigned i, j, len;
    for (i = 1, j = 0; i < n; ++i) {
        unsigned bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) {
            double t = re[i]; re[i] = re[j]; re[j] = t;
            t = im[i]; im[i] = im[j]; im[j] = t;
        }
    }
    for (len = 2; len <= n; len <<= 1) {
        const double ang = -2.0 * M_PI / (double)len;
        const double wr0 = cos(ang), wi0 = sin(ang);
        for (i = 0; i < n; i += len) {
            double wr = 1.0, wi = 0.0;
            for (j = 0; j < len/2; ++j) {
                const unsigned p = i+j, q = p+len/2;
                const double tr = wr*re[q] - wi*im[q];
                const double ti = wr*im[q] + wi*re[q];
                re[q] = re[p] - tr; im[q] = im[p] - ti;
                re[p] += tr;       im[p] += ti;
                const double nwr = wr*wr0 - wi*wi0;
                wi = wr*wi0 + wi*wr0; wr = nwr;
            }
        }
    }
}

static int solve3(double m[3][4], double x[3])
{
    unsigned i, j, k, p;
    for (i = 0; i < 3; ++i) {
        p = i;
        for (j = i+1; j < 3; ++j)
            if (fabs(m[j][i]) > fabs(m[p][i])) p = j;
        if (fabs(m[p][i]) < 1e-18) return 0;
        if (p != i) for (k = i; k < 4; ++k) {
            double t = m[i][k]; m[i][k] = m[p][k]; m[p][k] = t;
        }
        for (j = i+1; j < 3; ++j) {
            const double q = m[j][i] / m[i][i];
            for (k = i; k < 4; ++k) m[j][k] -= q*m[i][k];
        }
    }
    for (i = 3; i-- > 0;) {
        double s = m[i][3];
        for (j = i+1; j < 3; ++j) s -= m[i][j]*x[j];
        x[i] = s/m[i][i];
    }
    return 1;
}

static fit_t sine_fit(double f)
{
    // 对给定频率 f，拟合三个未知数 a、b、c。先建立 3x3 线性方程组，
    // 再用 solve3() 解出系数和均方误差。
    double ss=0, cc=0, sc=0, s1=0, c1=0, ys=0, yc=0, y1=0;
    double m[3][4], x[3];
    unsigned i;
    for (i = 0; i < TGG_N; ++i) {
        const double t = (double)i / TGG_FS;
        const double s = sin(2.0*M_PI*f*t), c = cos(2.0*M_PI*f*t);
        ss += s*s; cc += c*c; sc += s*c; s1 += s; c1 += c;
        ys += theta[i]*s; yc += theta[i]*c; y1 += theta[i];
    }
    m[0][0]=ss; m[0][1]=sc; m[0][2]=s1; m[0][3]=ys;
    m[1][0]=sc; m[1][1]=cc; m[1][2]=c1; m[1][3]=yc;
    m[2][0]=s1; m[2][1]=c1; m[2][2]=TGG_N; m[2][3]=y1;
    fit_t out = {0,0,0,0};
    if (!solve3(m, x)) { out.mse = 1e30; return out; }
    out.a=x[0]; out.b=x[1]; out.c=x[2];
    for (i = 0; i < TGG_N; ++i) {
        const double t=(double)i/TGG_FS;
        const double y=out.a*sin(2.0*M_PI*f*t)+out.b*cos(2.0*M_PI*f*t)+out.c;
        const double e=theta[i]-y; out.mse += e*e;
    }
    out.mse /= TGG_N;
    return out;
}

static double maxd(double a, double b) { return a > b ? a : b; }
static double mind(double a, double b) { return a < b ? a : b; }

void tgg_process_frame(const uint16_t raw[TGG_N], double vmax,
                       double min_frequency, double max_frequency,
                       tgg_result_t *r)
{
    unsigned i, k, peak = 0;
    int have_peak = 0;
    double mean=0, df=TGG_FS/TGG_N;
    if (vmax <= 0) vmax = 1.0;
    if (min_frequency < 0) min_frequency = 0;
    if (max_frequency > TGG_FS/2) max_frequency = TGG_FS/2;
    // ADC 输出是 0..4095，对应 XADC 的 0..1 V 单极性输入。
    for (i=0; i<TGG_N; ++i) {
        double v=(double)raw[i]/4095.0; // VP/VN unipolar full scale is 1 V
        double q=v/vmax;
        if (q<0) q=0; if (q>1) q=1;
        theta[i]=asin(sqrt(q)); mean+=theta[i];
    }
    mean/=TGG_N;
    // FFT 只分析交流部分，所以先减去整帧平均值（去掉静态偏置）。
    for (i=0; i<TGG_N; ++i) { fft_re[i]=theta[i]-mean; fft_im[i]=0; }
    fft(fft_re, fft_im, TGG_N);
    for (k=0; k<=TGG_N/2; ++k) {
        amplitude[k]=hypot(fft_re[k],fft_im[k])/TGG_N;
        if (k && k<TGG_N/2) amplitude[k]*=2;
        const double f=(double)k*df;
        if (f>=min_frequency && f<=max_frequency &&
            (!have_peak || amplitude[k]>amplitude[peak])) {
            peak=k;
            have_peak=1;
        }
    }
    if (!have_peak) { min_frequency=0; max_frequency=TGG_FS/2; peak=0; }
    r->peak_frequency=peak*df; r->peak_amplitude=amplitude[peak];
    r->refined_frequency=r->peak_frequency;
    r->refined_amplitude=r->peak_amplitude;
    if (peak>0 && peak<TGG_N/2) {
        const double y1=amplitude[peak-1], y2=amplitude[peak], y3=amplitude[peak+1];
        const double den=y1-2*y2+y3;
        if (fabs(den)>1e-20) {
            double d=0.5*(y1-y3)/den;
            if (d>1) d=1; if (d<-1) d=-1;
            r->refined_frequency=(peak+d)*df;
            r->refined_amplitude=y2-0.25*(y1-y3)*d;
        }
    }
    {
        // FFT 只能把频率定位到离散格点。这里在插值峰附近取小区间，
        // 用黄金分割搜索使正弦拟合均方误差最小的连续频率。
        double lo=maxd(min_frequency,r->refined_frequency-df);
        double hi=mind(max_frequency,r->refined_frequency+df);
        const double gr=(sqrt(5.0)-1.0)/2.0;
        double x1=hi-gr*(hi-lo), x2=lo+gr*(hi-lo);
        fit_t f1=sine_fit(x1), f2=sine_fit(x2);
        unsigned it;
        for (it=0; it<60 && hi>lo+1e-10; ++it) {
            if (f1.mse > f2.mse) { lo=x1; x1=x2; f1=f2; x2=lo+gr*(hi-lo); f2=sine_fit(x2); }
            else { hi=x2; x2=x1; f2=f1; x1=hi-gr*(hi-lo); f1=sine_fit(x1); }
        }
        r->fitted_frequency=(lo+hi)*0.5;
        fit_t ff=sine_fit(r->fitted_frequency);
        r->fitted_amplitude=hypot(ff.a,ff.b);
        r->fitted_phase=atan2(ff.b,ff.a);
        r->fitted_offset=ff.c;
        double var=0;
        for(i=0;i<TGG_N;++i) { const double d=theta[i]-mean; var+=d*d; }
        r->r_squared=(var>0)?1.0-ff.mse/(var/TGG_N):0;
    }
}

static void print_fixed(const char *name, double v, unsigned decimals)
{
    long long scale=1, q, i;
    for(i=0;i<decimals;++i) scale*=10;
    q=(long long)(v*scale + (v>=0 ? 0.5 : -0.5));
    printf("%s %lld.%0*lld\n", name, q/scale, (int)decimals, llabs(q%scale));
}

void tgg_print_result(const tgg_result_t *r)
{
    print_fixed("FFT peak frequency (Hz):", r->peak_frequency, 4);
    print_fixed("FFT peak amplitude (rad):", r->peak_amplitude, 8);
    print_fixed("FFT interpolated frequency (Hz):", r->refined_frequency, 4);
    print_fixed("FFT interpolated amplitude (rad):", r->refined_amplitude, 8);
    print_fixed("Final sine-fit frequency (Hz):", r->fitted_frequency, 4);
    print_fixed("Final sine-fit amplitude (rad):", r->fitted_amplitude, 8);
    print_fixed("Fitted phase (rad):", r->fitted_phase, 8);
    print_fixed("Fitted offset angle (rad):", r->fitted_offset, 8);
    print_fixed("R squared:", r->r_squared, 4);
}
