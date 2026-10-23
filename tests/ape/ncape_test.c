/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * Standalone test of src/engine/ncape.c against a reference decode:
 *   ncape_test file.ape reference.wav
 * checks the stream info, a full decode (bit-exact against the WAV), seeking to many positions and two
 * streams decoding in turn. Build and run: tests/ape/run.sh
 */
#include "ncape.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int fails;
#define CHECK(c, ...) do { if (!(c)) { fails++; printf("FAIL: " __VA_ARGS__); printf("\n"); } } while (0)

static unsigned char *load(const char *p, size_t *n)
{
    FILE *f = fopen(p, "rb"); unsigned char *b;
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); *n = (size_t)ftell(f); fseek(f, 0, SEEK_SET);
    b = (unsigned char *)malloc(*n); if (fread(b, 1, *n, f) != *n) { free(b); b = NULL; }
    fclose(f); return b;
}

/* sample i (interleaved index) of the reference WAV as a float in -1..1 */
static const unsigned char *g_pcm; static int g_bits, g_ch;
static float refsample(size_t i)
{
    if (g_bits == 8) return ((int)g_pcm[i] - 128) / 128.0f;
    if (g_bits == 16) return (short)(g_pcm[2 * i] | (g_pcm[2 * i + 1] << 8)) / 32768.0f;
    { int v = g_pcm[3 * i] | (g_pcm[3 * i + 1] << 8) | (g_pcm[3 * i + 2] << 16); if (v & 0x800000) v -= 1 << 24; return v / 8388608.0f; }
}

static size_t compare(const float *got, uint64_t start, uint64_t frames)
{
    uint64_t i; int c;
    for (i = 0; i < frames; i++)
        for (c = 0; c < g_ch; c++)
            if (got[i * g_ch + c] != refsample((size_t)((start + i) * g_ch + c))) return (size_t)(start + i + 1);
    return 0;
}

int main(int argc, char **argv)
{
    size_t wn, off = 12, dlen = 0; unsigned char *wav; FILE *f; ncape *m, *m2; const ncape_info *in;
    uint64_t total, got; float *buf, *full; int k;
    if (argc < 3) { fprintf(stderr, "usage: ncape_test file.ape reference.wav\n"); return 2; }
    wav = load(argv[2], &wn);
    if (!wav || wn < 44 || memcmp(wav, "RIFF", 4)) { fprintf(stderr, "bad WAV\n"); return 2; }
    while (off + 8 <= wn) {                      /* find fmt and data chunks */
        unsigned sz = wav[off + 4] | (wav[off + 5] << 8) | (wav[off + 6] << 16) | ((unsigned)wav[off + 7] << 24);
        if (!memcmp(wav + off, "fmt ", 4)) { g_ch = wav[off + 10]; g_bits = wav[off + 22]; }
        if (!memcmp(wav + off, "data", 4)) { g_pcm = wav + off + 8; dlen = sz; if (off + 8 + dlen > wn) dlen = wn - off - 8; break; }
        off += 8 + sz + (sz & 1);
    }
    f = fopen(argv[1], "rb");
    m = ncape_open(f);
    if (!m) { printf("FAIL: cannot open %s\n", argv[1]); return 1; }
    in = ncape_get_info(m);
    total = dlen / (size_t)(g_ch * g_bits / 8);
    printf("%s: v%u level %u, %u ch, %u Hz, %u bit, %llu frames, %llu audio bytes\n", argv[1], in->version, in->level, in->channels, in->rate, in->bits,
           (unsigned long long)in->length, (unsigned long long)in->audio_bytes);
    CHECK((int)in->channels == g_ch && (int)in->bits == g_bits, "format mismatch");
    CHECK(in->length == total, "length %llu != reference %llu", (unsigned long long)in->length, (unsigned long long)total);

    full = (float *)malloc((size_t)total * g_ch * sizeof(float));
    got = ncape_read_f32(m, full, total + 1000);
    CHECK(got == total, "decoded %llu frames, expected %llu", (unsigned long long)got, (unsigned long long)total);
    { size_t bad = compare(full, 0, got); CHECK(!bad, "full decode differs from the reference at frame %zu", bad ? bad - 1 : 0); }
    CHECK(ncape_read_f32(m, full, 10) == 0, "data after the end");
    CHECK(ncape_cursor(m) == total, "cursor at end");

    buf = (float *)malloc(8192 * g_ch * sizeof(float));
    srand(1234);
    for (k = 0; k < 200; k++) {                  /* random seeks, short reads */
        uint64_t n, p = k == 0 ? 0 : k == 1 ? total - 1 : k == 2 ? total : (((uint64_t)rand() << 15) ^ (uint64_t)rand()) % (total + 1);
        uint64_t exp;
        ncape_seek(m, p);
        CHECK(ncape_cursor(m) == p, "cursor after seek %llu", (unsigned long long)p);
        exp = total - p < 5000 ? total - p : 5000;
        n = ncape_read_f32(m, buf, 5000);
        CHECK(n == exp, "seek %llu: read %llu, expected %llu", (unsigned long long)p, (unsigned long long)n, (unsigned long long)exp);
        { size_t bad = compare(buf, p, n); CHECK(!bad, "after seek to %llu: differs at frame %zu", (unsigned long long)p, bad ? bad - 1 : 0); }
    }
    /* seeks across APE frame boundaries */
    for (k = 1; k * 294912ull < total + 294912ull; k++) {
        uint64_t b = k * 294912ull; int d;
        for (d = -3; d <= 3; d += 3) {
            uint64_t p = b + d, n, exp; if (b + d < 1 || p >= total) continue;
            ncape_seek(m, p); n = ncape_read_f32(m, buf, 100);
            exp = total - p < 100 ? total - p : 100;
            CHECK(n == exp && !compare(buf, p, n), "frame boundary %llu", (unsigned long long)p);
        }
    }
    /* two streams in turn (libdemac has one static decoder): each must keep its own position */
    ncape_seek(m, 0);
    m2 = ncape_open(fopen(argv[1], "rb"));
    CHECK(m2 != NULL, "second open");
    if (m2) {
        uint64_t pa = 0, pb = total / 2;
        ncape_seek(m2, pb);
        for (k = 0; k < 60; k++) {
            uint64_t n = ncape_read_f32(m, buf, 1000);
            CHECK(!compare(buf, pa, n), "stream A at %llu", (unsigned long long)pa); pa += n;
            n = ncape_read_f32(m2, buf, 777);
            CHECK(!compare(buf, pb, n), "stream B at %llu", (unsigned long long)pb); pb += n;
        }
        ncape_close(m2);
    }
    { ncape_info pi; FILE *g = fopen(argv[1], "rb"); CHECK(g && ncape_probe(g, &pi) == 0 && pi.length == total, "probe"); if (g) fclose(g); }
    ncape_close(m);
    printf(fails ? "RESULT: %d failure(s)\n" : "RESULT: ok\n", fails);
    free(full); free(buf); free(wav);
    return fails != 0;
}
