#include "Aftertone.h"
#include <math.h>
#include <stdatomic.h>
#include <stdlib.h>
#include <string.h>

#define PI 3.141592653589793
#define N 2048
// In-place radix-2 FFT, shared by the spectrum and pitch-class analysis.
static void magnitudes(float *real,float *imag,int n) {
    memset(imag,0,n*sizeof(float));
    for(int i=0;i<n;i++) {
        real[i]*=.5f-.5f*cosf((float)(2*PI*i/(n-1)));
    }
    for(int i=1,j=0;i<n;i++) {
        int bit=n>>1; while(j&bit) { j^=bit; bit>>=1; } j^=bit;
        if(i<j) { float t=real[i]; real[i]=real[j]; real[j]=t; }
    }
    for(int len=2;len<=n;len*=2) {
        float a=(float)(-2*PI/len), wr=cosf(a), wi=sinf(a);
        for(int base=0;base<n;base+=len) {
            float r=1, im=0;
            for(int j=0;j<len/2;j++) {
                int p=base+j,q=p+len/2;
                float x=real[q]*r-imag[q]*im, y=real[q]*im+imag[q]*r;
                real[q]=real[p]-x; imag[q]=imag[p]-y;
                real[p]+=x; imag[p]+=y;
                float next=r*wr-im*wi; im=r*wi+im*wr; r=next;
            }
        }
    }
    for(int i=0;i<n/2;i++) real[i]=hypotf(real[i],imag[i]);
}
struct ATScope { atomic_flag lock; float ring[N]; int cursor; };
ATScope *at_scope_create(void) {
    ATScope *s=calloc(1,sizeof(*s)); if(s) atomic_flag_clear(&s->lock); return s;
}
void at_scope_destroy(ATScope *s) { free(s); }
void at_scope_push(ATScope *s,const float *samples,int count) {
    if(atomic_flag_test_and_set_explicit(&s->lock,memory_order_acquire)) return;
    for(int i=0;i<count;i++) { s->ring[s->cursor]=samples[i]; s->cursor=(s->cursor+1)%N; }
    atomic_flag_clear_explicit(&s->lock,memory_order_release);
}
void at_scope_read(ATScope *s,float *wave,float *spectrum,float rate) {
    float r[N],im[N];
    if(atomic_flag_test_and_set_explicit(&s->lock,memory_order_acquire)) return;
    for(int i=0;i<N;i++) r[i]=s->ring[(s->cursor+i)%N];
    atomic_flag_clear_explicit(&s->lock,memory_order_release);
    for(int i=0;i<128;i++) wave[i]=r[N-512+i*4];
    magnitudes(r,im,N);
    for(int b=0;b<64;b++) {
        float top=fminf(20000,rate/2);
        int lo=(int)fmaxf(1,28*powf(top/28,b/64.f)*N/rate);
        int hi=(int)fminf(N/2,fmaxf(lo+1,28*powf(top/28,(b+1)/64.f)*N/rate));
        float peak=0; for(int i=lo;i<hi;i++) peak=fmaxf(peak,r[i]*4/N);
        spectrum[b]=fminf(1,fmaxf(0,(20*log10f(peak+1e-8f)+66)/66));
    }
}

void at_analyze(const float *samples,int64_t frames,double rate,float *overview,int bins,int *bpm,int *key) {
    *bpm=0; *key=-1;
    memset(overview,0,bins*sizeof(float));
    for(int64_t i=0;i<frames;i++) {
        int b=(int)(i*bins/frames);
        overview[b]=fmaxf(overview[b],fmaxf(fabsf(samples[i*2]),fabsf(samples[i*2+1])));
    }
    int hop=(int)fmax(1,round(rate*.01));
    int64_t length=(int64_t)fmin(frames,rate*90);
    int64_t start=(frames-length)/2;
    int count=(int)(length/hop); if(count<100) return;
    float *onset=calloc(count,sizeof(float)); if(!onset) return;
    // Positive spectral flux isolates transients even under sustained chords.
    // Window length follows sample rate so beat timing survives hi-res imports.
    int win=512;
    while(win<rate*.04 && win<8192) win*=2;
    float *real=calloc(win,sizeof(float)), *imag=calloc(win,sizeof(float));
    float *prior=calloc(win/2,sizeof(float));
    if(!real || !imag || !prior) {free(real);free(imag);free(prior);free(onset);return;}
    for(int n=0;n<count;n++) {
        int64_t base=start+(int64_t)n*hop;
        if(base+win>frames) break;
        for(int i=0;i<win;i++) real[i]=.5f*(samples[2*(base+i)]+samples[2*(base+i)+1]);
        magnitudes(real,imag,win);
        for(int i=1;i<win/2;i++) {
            float amplitude=log1pf(real[i]);
            if(n>0) onset[n]+=fmaxf(0,amplitude-prior[i]);
            prior[i]=amplitude;
        }
    }
    free(real); free(imag); free(prior);
    double best=.12; int lag=0;
    for(int d=30;d<=100 && d<count/3;d++) {
        double dot=0,a=0,b=0;
        for(int j=d;j<count;j++) {
            dot+=onset[j]*onset[j-d]; a+=onset[j]*onset[j]; b+=onset[j-d]*onset[j-d];
        }
        double score=dot/sqrt(a*b+1e-12);
        if(score>best+.0001) {best=score; lag=d;}
    }
    free(onset); if(lag) *bpm=(int)round(60*rate/(lag*hop));

    // Spectral peaks vote for pitch classes; compare against major/minor profiles.
    double chroma[12]={0};
    enum { K=8192 };
    float *r=malloc(K*sizeof(float)),*im=malloc(K*sizeof(float));
    if(!r || !im) { free(r); free(im); return; }
    for(int64_t p=start;p+K<=start+length;p+=(int64_t)(rate*.24)) {
        for(int i=0;i<K;i++) r[i]=.5f*(samples[2*(p+i)]+samples[2*(p+i)+1]);
        magnitudes(r,im,K);
        for(int i=2;i<K/2-1;i++) {
            double hz=i*rate/K;
            if(hz<55 || hz>3000 || r[i]<.03 || r[i]<r[i-1] || r[i]<=r[i+1]) continue;
            double offset=.5*(r[i-1]-r[i+1])/(r[i-1]-2*r[i]+r[i+1]);
            int midi=(int)round(69+12*log2((i+offset)*rate/(K*440.)));
            chroma[midi%12]+=sqrt(r[i]);
        }
    }
    free(r); free(im);
    const double profiles[2][12]={{6.35,2.23,3.48,2.33,4.38,4.09,2.52,5.19,2.39,3.66,2.29,2.88},
        {6.33,2.68,3.52,5.38,2.6,3.53,2.54,4.75,3.98,2.69,3.34,3.17}};
    double mean=0; for(int i=0;i<12;i++) mean+=chroma[i]/12;
    best=.35;
    for(int mode=0;mode<2;mode++) for(int root=0;root<12;root++) {
        double m=0,dot=0,a=0,b=0;
        for(int i=0;i<12;i++) m+=profiles[mode][i]/12;
        for(int i=0;i<12;i++) {
            double x=chroma[(i+root)%12]-mean,y=profiles[mode][i]-m;
            dot+=x*y; a+=x*x; b+=y*y;
        }
        double score=dot/sqrt(a*b+1e-12);
        if(score>best) {best=score; *key=root+12*mode;}
    }
}
