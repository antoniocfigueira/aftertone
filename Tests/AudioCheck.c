#include "Aftertone.h"
#ifdef NDEBUG
#undef NDEBUG
#endif
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { RATE=44100, BLOCK=1024 };
static ATSettings neutral(void) {
    ATSettings s={0}; s.width=1; s.wetLow=80; s.wetHigh=12000; s.size=.5f; return s;
}
static void transport(void) {
    float input[2*BLOCK],l[BLOCK],r[BLOCK];
    for(int i=0;i<BLOCK;i++) { input[2*i]=.6f*sinf(i*.1f); input[2*i+1]=-.4f*cosf(i*.37f); }
    for(int rev=0;rev<=1;rev++) {
        ATVoice *v=at_create(input,BLOCK,RATE); assert(v);
        at_settings(v,neutral()); at_start(v,rev?BLOCK-1:0,rev);
        at_render(v,l,r,BLOCK);
        for(int i=0;i<BLOCK;i++) {
            int j=rev?BLOCK-1-i:i;
            assert(fabsf(l[i]-input[2*j])<1e-6);
            assert(fabsf(r[i]-input[2*j+1])<1e-6);
        }
        assert(at_elapsed(v)==BLOCK);
        at_render(v,l,r,BLOCK); assert(l[0]==0 && r[BLOCK-1]==0); at_destroy(v);
    }
    ATVoice *v=at_create(input,BLOCK,RATE);
    ATSettings hot=neutral(); hot.width=0; hot.preampDB=18; hot.eq[5]=15;
    hot.magic=1; hot.bandDrive[0]=.6f; hot.bandDrive[1]=.3f; hot.drive=.4f;
    at_settings(v,hot); at_render(v,l,r,BLOCK);
    float diff=0;
    for(int i=0;i<BLOCK;i++) {
        assert(isfinite(l[i]) && fabsf(l[i])<=1.000001f && l[i]==r[i]);
        diff+=fabsf(l[i]-input[2*i]);
    }
    assert(diff>10); at_destroy(v);
}
static void reverb(void) {
    float impulse[2]={1,1},l[BLOCK],r[BLOCK];
    for(int i=0;i<4;i++) {
        ATVoice *v=at_create(impulse,1,RATE); ATSettings s=neutral();
        s.wet=1; s.space=i; at_settings(v,s);
        double tail=0;
        for(int block=0;block<20;block++) {
            at_render(v,l,r,BLOCK);
            for(int k=0;k<BLOCK;k++) tail+=fabs(l[k])+fabs(r[k]);
        }
        assert(tail>.01); at_destroy(v);
    }
}
static void analysis(void) {
    int frames=RATE*12;
    float *pcm=calloc((size_t)frames*2,sizeof(float)); assert(pcm);
    float overview[64]; int bpm,key;
    at_analyze(pcm,frames,RATE,overview,64,&bpm,&key); assert(bpm==0 && key==-1);
    for(int i=0;i<frames;i++) {
        double t=(double)i/RATE;
        double chord=.12*sin(6.2831853*261.626*t)+.10*sin(6.2831853*329.628*t)+.10*sin(6.2831853*391.995*t);
        int click=i%(RATE/2); double beat=.7*exp(-click/180.)*cos(click*.06);
        pcm[2*i]=pcm[2*i+1]=(float)(chord+beat);
    }
    at_analyze(pcm,frames,RATE,overview,64,&bpm,&key);
    printf("Reference fixture: %d BPM, key index %d\n",bpm,key);
    assert(abs(bpm-120)<=2 && key==0 && overview[0]>.4f);
    ATScope *scope=at_scope_create(); float wave[128],spec[64];
    at_scope_push(scope,pcm,2048); at_scope_read(scope,wave,spec,RATE);
    float peak=0; for(int i=0;i<64;i++) peak=fmaxf(peak,spec[i]);
    assert(peak>.3f && wave[0]==pcm[1536]); at_scope_destroy(scope); free(pcm);
}
int main(void) { transport(); reverb(); analysis(); puts("Audio checks passed."); return 0; }

