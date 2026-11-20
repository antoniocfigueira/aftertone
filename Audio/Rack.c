#include "Aftertone.h"
#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#define PI 3.141592653589793
static const float centers[] = {31,63,125,250,500,1000,2000,4000,8000,16000};
typedef struct { float b0,b1,b2,a1,a2,z1[2],z2[2]; } Biquad;
typedef struct { float *data; int capacity, cursor; float damped; } Delay;
struct ATVoice {
    const float *samples;
    int64_t frames, cursor, elapsed;
    atomic_llong published, clock;
    double rate;
    int direction, dirty;
    atomic_flag lock;
    ATSettings pending, fx;
    Biquad eq[10];
    float crossover[2][2], alpha[2], bass[2], wetBass[2], wetAir[2];
    float wetHP, wetLP, gain, drive, drives[3], envelope, limit, release, smooth;
    Delay delays[8];
    int lengths[8];
    float feedback;
};

static float alpha(double hz, double rate) { return 1-expf((float)(-2*PI*hz/rate)); }
static float saturate(float x, float drive) {
    return drive > 1.0001f ? tanhf(x*drive)/tanhf(drive) : x;
}
static float filter(Biquad *b, int c, float x) {
    float y=b->b0*x+b->z1[c];
    b->z1[c]=b->b1*x-b->a1*y+b->z2[c];
    b->z2[c]=b->b2*x-b->a2*y;
    return y;
}
static void configure(ATVoice *v) {
    ATSettings s=v->fx;
    for(int i=0;i<10;i++) {
        double w=2*PI*fmin(centers[i],v->rate*.46)/v->rate;
        double a=sin(w)/(2*1.414), g=pow(10,s.eq[i]/40), den=1+a/g;
        Biquad *b=&v->eq[i];
        b->b0=(1+a*g)/den; b->b1=-2*cos(w)/den; b->b2=(1-a*g)/den;
        b->a1=b->b1; b->a2=(1-a/g)/den;
    }
    v->drive=1+15*s.drive;
    for(int i=0;i<3;i++) v->drives[i]=1+15*s.bandDrive[i];
    v->gain=powf(10,s.preampDB/20);
    v->wetHP=alpha(s.wetLow,v->rate); v->wetLP=alpha(s.wetHigh,v->rate);
    // Four room tunings with independent delay density and decay.
    static const float times[4][8]={
        {23,29,31,37,41,43,47,53},{37,41,43,47,53,59,67,71},
        {11,13,17,19,23,29,31,37},{43,53,61,71,79,89,97,103}};
    int space=s.space>=0 && s.space<4?s.space:0;
    for(int i=0;i<8;i++) v->lengths[i]=(int)fmax(1,times[space][i]*(.55+.9*s.size)*.001*v->rate);
    v->feedback=(space==2?.81f:.65f)+.15f*s.size;
}
ATVoice *at_create(const float *samples,int64_t frames,double rate) {
    ATVoice *v=calloc(1,sizeof(*v)); if(!v) return NULL;
    v->samples=samples; v->frames=frames; v->rate=rate; v->direction=1;
    atomic_flag_clear(&v->lock); atomic_init(&v->published,0); atomic_init(&v->clock,0);
    v->alpha[0]=alpha(220,rate); v->alpha[1]=alpha(3200,rate);
    v->release=1-expf(-1/(.09*rate)); v->smooth=1-expf(-1/(.005*rate));
    v->limit=1; v->pending.width=1; v->pending.wetLow=80; v->pending.wetHigh=12000; v->dirty=1;
    for(int i=0;i<8;i++) {
        v->delays[i].capacity=(int)(rate*.16)+2;
        v->delays[i].data=calloc(v->delays[i].capacity,sizeof(float));
        if(!v->delays[i].data) { at_destroy(v); return NULL; }
    }
    return v;
}
void at_destroy(ATVoice *v) {
    if(!v) return;
    for(int i=0;i<8;i++) free(v->delays[i].data);
    free(v);
}
void at_settings(ATVoice *v,ATSettings s) {
    while(atomic_flag_test_and_set_explicit(&v->lock,memory_order_acquire)) {}
    v->pending=s; v->dirty=1;
    atomic_flag_clear_explicit(&v->lock,memory_order_release);
}
// Called on a stopped voice, before the engine starts pulling samples.
void at_start(ATVoice *v,int64_t frame,int reverse) {
    v->cursor=frame; v->direction=reverse?-1:1; v->elapsed=0;
    atomic_store(&v->published,frame); atomic_store(&v->clock,0);
}
int64_t at_position(ATVoice *v) { return atomic_load(&v->published); }
int64_t at_elapsed(ATVoice *v) { return atomic_load(&v->clock); }

static void room(ATVoice *v,float x[2]) {
    float taps[8], sum=0, wet[2]={0};
    for(int i=0;i<8;i++) {
        Delay *d=&v->delays[i];
        int read=d->cursor-v->lengths[i]; if(read<0) read+=d->capacity;
        float t=d->data[read];
        d->damped+=(t-d->damped)*(1-.87f*v->fx.damping);
        taps[i]=d->damped; sum+=taps[i];
        wet[i%2]+=t*(i<4?.25f:-.25f);
    }
    // Orthogonal Householder feedback keeps the diffuse tail stable.
    for(int i=0;i<8;i++) {
        Delay *d=&v->delays[i];
        d->data[d->cursor]=x[i%2]*(i%3?1:-1)+(taps[i]-.25f*sum)*v->feedback;
        if(++d->cursor==d->capacity) d->cursor=0;
    }
    for(int c=0;c<2;c++) {
        v->wetBass[c]+=v->wetHP*(wet[c]-v->wetBass[c]);
        v->wetAir[c]+=v->wetLP*(wet[c]-v->wetBass[c]-v->wetAir[c]);
        x[c]=x[c]*(1-v->fx.wet)+v->wetAir[c]*v->fx.wet;
    }
}
void at_render(ATVoice *v,float *left,float *right,int frames) {
    if(!atomic_flag_test_and_set_explicit(&v->lock,memory_order_acquire)) {
        int changed=v->dirty;
        if(changed) {v->fx=v->pending; v->dirty=0;}
        atomic_flag_clear_explicit(&v->lock,memory_order_release);
        if(changed) configure(v);
    }
    ATSettings *s=&v->fx;
    for(int n=0;n<frames;n++) {
        float x[2]={0};
        if(v->cursor>=0 && v->cursor<v->frames) {
            x[0]=v->samples[v->cursor*2]; x[1]=v->samples[v->cursor*2+1]; v->cursor+=v->direction;
        }
        for(int c=0;c<2;c++) {
            float y=x[c];
            for(int i=0;i<10;i++) if(s->eq[i]!=0) y=filter(&v->eq[i],c,y);
            if(s->bandDrive[0]+s->bandDrive[1]+s->bandDrive[2]>0) {
                float *lp=v->crossover[c];
                for(int i=0;i<2;i++) lp[i]+=v->alpha[i]*(y-lp[i]);
                y=saturate(lp[0],v->drives[0])+saturate(lp[1]-lp[0],v->drives[1])+saturate(y-lp[1],v->drives[2]);
            }
            x[c]=saturate(y,v->drive);
        }
        if(s->magic>0) {
            float peak=fmaxf(fabsf(x[0]),fabsf(x[1]));
            v->envelope+=(peak-v->envelope)*(peak>v->envelope?v->smooth:v->release);
            float comp=powf(fmaxf(1,v->envelope/.32f),-.55f*s->magic);
            for(int c=0;c<2;c++) {
                v->bass[c]+=v->alpha[0]*(x[c]-v->bass[c]);
                float shaped=x[c]+s->magic*(.12f*v->bass[c]+.055f*(x[c]-v->bass[c]));
                x[c]=saturate(shaped*comp,1+1.8f*s->magic);
            }
        }
        if(s->wet>0) room(v,x);
        float mid=.5f*(x[0]+x[1]), side=.5f*(x[0]-x[1])*s->width;
        x[0]=(mid+side)*v->gain; x[1]=(mid-side)*v->gain;
        float peak=fmaxf(fabsf(x[0]),fabsf(x[1]));
        float target=peak>1?.999f/peak:1;
        v->limit=fminf(target,v->limit+v->release*(1-v->limit));
        left[n]=x[0]*v->limit; right[n]=x[1]*v->limit;
    }
    v->elapsed+=frames;
    atomic_store(&v->published,v->cursor); atomic_store(&v->clock,v->elapsed);
}
