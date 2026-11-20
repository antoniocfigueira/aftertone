#ifndef AFTERTONE_H
#define AFTERTONE_H
#include <stdint.h>
#include <stddef.h>
typedef struct ATVoice ATVoice;
typedef struct ATScope ATScope;
typedef struct {
    float eq[10], bandDrive[3];
    float drive, width, preampDB, magic, wet, size, damping, wetLow, wetHigh;
    int space;
} ATSettings;
ATVoice *at_create(const float *samples, int64_t frames, double rate);
void at_destroy(ATVoice *v);
void at_settings(ATVoice *v, ATSettings settings);
void at_start(ATVoice *v, int64_t frame, int reverse);
void at_render(ATVoice *v, float *left, float *right, int frames);
int64_t at_position(ATVoice *v);
int64_t at_elapsed(ATVoice *v);
ATScope *at_scope_create(void);
void at_scope_destroy(ATScope *s);
void at_scope_push(ATScope *s, const float *samples, int count);
void at_scope_read(ATScope *s, float *wave, float *spectrum, float rate);
void at_analyze(const float *samples, int64_t frames, double rate, float *overview, int bins, int *bpm, int *key);
int at_decode(const char *source, const char *destination, int *rate, char *error, size_t capacity);
#endif
