#include "Aftertone.h"
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/error.h>
#include <libavutil/mem.h>
#include <stdio.h>
#include <errno.h>

typedef struct { SwrContext *mix; FILE *file; uint8_t *pcm; unsigned bytes; int rate; } Writer;
static int convert(Writer *w,AVFrame *f) {
    int e;
    if(!w->mix) {
        if(!f || f->sample_rate<4000 || f->sample_rate>384000) return AVERROR_INVALIDDATA;
        AVChannelLayout stereo=AV_CHANNEL_LAYOUT_STEREO;
        w->rate=f->sample_rate;
        e=swr_alloc_set_opts2(&w->mix,&stereo,AV_SAMPLE_FMT_FLT,w->rate,&f->ch_layout,
                              f->format,f->sample_rate,0,NULL);
        if(e<0 || (e=swr_init(w->mix))<0) return e;
    }
    if(f && f->sample_rate!=w->rate) return AVERROR_PATCHWELCOME;
    int n=swr_get_out_samples(w->mix,f?f->nb_samples:0);
    if(n<=0) return n;
    av_fast_malloc(&w->pcm,&w->bytes,(size_t)n*2*sizeof(float));
    if(!w->pcm) return AVERROR(ENOMEM);
    e=swr_convert(w->mix,&w->pcm,n,f?(const uint8_t **)f->extended_data:NULL,f?f->nb_samples:0);
    if(e<0) return e;
    return fwrite(w->pcm,2*sizeof(float),e,w->file)==(size_t)e?0:AVERROR(EIO);
}
static int drain(AVCodecContext *codec,AVFrame *frame,Writer *w) {
    int e;
    while((e=avcodec_receive_frame(codec,frame))>=0) {
        e=convert(w,frame); av_frame_unref(frame); if(e<0) return e;
    }
    return e==AVERROR(EAGAIN)||e==AVERROR_EOF?0:e;
}
int at_decode(const char *source,const char *destination,int *rate,char *error,size_t capacity) {
    AVFormatContext *fmt=NULL; AVCodecContext *codec=NULL;
    AVPacket *packet=av_packet_alloc(); AVFrame *frame=av_frame_alloc();
    Writer w={0}; const AVCodec *decoder=NULL; int stream,e=AVERROR(ENOMEM);
    if(!packet || !frame) goto end;
    if((e=avformat_open_input(&fmt,source,NULL,NULL))<0 || (e=avformat_find_stream_info(fmt,NULL))<0) goto end;
    stream=av_find_best_stream(fmt,AVMEDIA_TYPE_AUDIO,-1,-1,&decoder,0);
    if(stream<0) { e=stream; goto end; }
    codec=avcodec_alloc_context3(decoder); if(!codec) {e=AVERROR(ENOMEM);goto end;}
    if((e=avcodec_parameters_to_context(codec,fmt->streams[stream]->codecpar))<0 ||
       (e=avcodec_open2(codec,decoder,NULL))<0) goto end;
    w.file=fopen(destination,"wb"); if(!w.file) {e=AVERROR(errno);goto end;}
    while((e=av_read_frame(fmt,packet))>=0) {
        if(packet->stream_index==stream) {
            e=avcodec_send_packet(codec,packet);
            if(e>=0) e=drain(codec,frame,&w);
        }
        av_packet_unref(packet); if(e<0) goto end;
    }
    if(e!=AVERROR_EOF) goto end;
    if((e=avcodec_send_packet(codec,NULL))<0 || (e=drain(codec,frame,&w))<0 ||
       (e=convert(&w,NULL))<0) goto end;
    if(ftell(w.file)<=0) e=AVERROR_INVALIDDATA;
end:
    if(w.file && fclose(w.file)!=0 && e>=0) e=AVERROR(EIO);
    if(e<0) {av_strerror(e,error,capacity); remove(destination);} else *rate=w.rate;
    av_free(w.pcm); swr_free(&w.mix); av_frame_free(&frame); av_packet_free(&packet);
    avcodec_free_context(&codec); avformat_close_input(&fmt);
    return e;
}
