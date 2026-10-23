/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * ncape - Monkey's Audio (.ape) reader on top of libdemac; see ncape.h.
 */
#include "ncape.h"
#include <stdlib.h>
#include <string.h>
#include "parser.h"
#include "decoder.h"

#ifdef _WIN32
#define NCAPE_FSEEK(f, o) _fseeki64((f), (__int64)(o), SEEK_SET)
#else
#define NCAPE_FSEEK(f, o) fseeko((f), (off_t)(o), SEEK_SET)
#endif

#define NCAPE_CHUNK  4608                 /* sample frames decoded per libdemac call */
#define NCAPE_INBUF  (32 * 1024)          /* libdemac wants one contiguous run of compressed bytes */
#define NCAPE_MAXSEEK (64u << 20)

struct ncape {
    FILE *f;
    ncape_info info;
    struct ape_ctx_t ctx;
    uint32_t *seek;                 /* absolute file offset of every APE frame (junk included) */
    uint32_t nframes, blocksperframe, finalblocks;
    uint32_t frame, inframe;        /* logical position: APE frame and sample frame within it */
    uint32_t dframe, ddone;         /* where the (shared) libdemac decoder is, while this stream owns it */
    int err;
    float scale;
};

/* the one libdemac decoder (its filter / range coder state is static): who owns it, and its input */
static volatile int g_lock;
static ncape *g_owner;
static unsigned char g_in[NCAPE_INBUF + 16];
static int g_inlen, g_firstbyte;
static int32_t g_d0[NCAPE_CHUNK], g_d1[NCAPE_CHUNK];

static void ncape_lock(void)   { while (__sync_lock_test_and_set(&g_lock, 1)) { } }
static void ncape_unlock(void) { __sync_lock_release(&g_lock); }

static uint32_t rd32(const unsigned char *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24); }

static long long ncape_file_size(FILE *f)
{
#ifdef _WIN32
    __int64 pos = _ftelli64(f), n;
    if (_fseeki64(f, 0, SEEK_END)) return -1;
    n = _ftelli64(f); _fseeki64(f, pos, SEEK_SET); return n;
#else
    off_t pos = ftello(f), n;
    if (fseeko(f, 0, SEEK_END)) return -1;
    n = ftello(f); fseeko(f, pos, SEEK_SET); return n;
#endif
}

/* parse the header at the start of f; fills ctx and *junk (leading ID3v2 tag size) */
static int ncape_parse(FILE *f, struct ape_ctx_t *ctx, ncape_info *info, uint32_t *junk)
{
    unsigned char buf[256];
    size_t n; uint32_t j = 0;
    long long fsize;
    if (NCAPE_FSEEK(f, 0)) return -1;
    n = fread(buf, 1, 10, f);
    if (n == 10 && memcmp(buf, "ID3", 3) == 0 && !((buf[6] | buf[7] | buf[8] | buf[9]) & 0x80)) {
        j = 10 + (((uint32_t)buf[6] << 21) | ((uint32_t)buf[7] << 14) | ((uint32_t)buf[8] << 7) | buf[9]);
        if (buf[5] & 0x10) j += 10;                           /* footer */
    }
    if (NCAPE_FSEEK(f, j)) return -1;
    memset(buf, 0, sizeof buf);
    n = fread(buf, 1, sizeof buf, f);
    if (n < 40) return -1;
    if (ape_parseheaderbuf(buf, ctx) < 0) return -1;
    if (ctx->fileversion < APE_MIN_VERSION || ctx->fileversion > APE_MAX_VERSION) return -1;
    if (ctx->fileversion >= 3980 && (ctx->descriptorlength < 52 || ctx->descriptorlength > 128 || ctx->headerlength < 24)) return -1;
    if (ctx->compressiontype < 1000 || ctx->compressiontype > 5000 || (ctx->compressiontype % 1000)) return -1;
    if ((ctx->bps != 8 && ctx->bps != 16 && ctx->bps != 24) || (ctx->channels != 1 && ctx->channels != 2)) return -1;
    if (!ctx->samplerate || ctx->samplerate > 768000 || !ctx->blocksperframe || !ctx->totalframes || ctx->totalframes > (1u << 24)) return -1;
    if (ctx->seektablelength > NCAPE_MAXSEEK) return -1;
    if (ctx->fileversion < 3980 && (ctx->formatflags & MAC_FORMAT_FLAG_CREATE_WAV_HEADER)) {
        /* the WAV header is not stored in the file although its length is recorded */
        ctx->seektablefilepos -= ctx->wavheaderlength; ctx->firstframe -= ctx->wavheaderlength;
        ctx->wavheaderlength = 0;
    }
    ctx->seektablefilepos += (int)j; ctx->firstframe += j;
    *junk = j;
    memset(info, 0, sizeof *info);
    info->version = ctx->fileversion; info->level = ctx->compressiontype;
    info->channels = ctx->channels; info->rate = ctx->samplerate; info->bits = ctx->bps;
    info->length = (uint64_t)ctx->finalframeblocks + (uint64_t)ctx->blocksperframe * (ctx->totalframes - 1);
    if (ctx->fileversion >= 3980 && (ctx->audiodatalength || ctx->audiodatalength_high))
        info->audio_bytes = (uint64_t)ctx->audiodatalength | ((uint64_t)ctx->audiodatalength_high << 32);
    else {
        fsize = ncape_file_size(f);
        if (fsize > (long long)ctx->firstframe + ctx->wavtaillength) info->audio_bytes = (uint64_t)(fsize - ctx->firstframe - ctx->wavtaillength);
    }
    return 0;
}

int ncape_probe(FILE *f, ncape_info *info)
{
    struct ape_ctx_t *ctx = (struct ape_ctx_t *)malloc(sizeof *ctx);
    uint32_t junk; int r;
    if (!ctx) return -1;
    r = ncape_parse(f, ctx, info, &junk);
    free(ctx);
    return r;
}

ncape *ncape_open(FILE *f)
{
    ncape *m; uint32_t junk, i; unsigned char *tab;
    if (!f) return NULL;
    m = (ncape *)calloc(1, sizeof *m);
    if (!m) { fclose(f); return NULL; }
    m->f = f;
    if (ncape_parse(f, &m->ctx, &m->info, &junk)) goto fail;
    m->nframes = m->ctx.totalframes; m->blocksperframe = m->ctx.blocksperframe; m->finalblocks = m->ctx.finalframeblocks;
    if (m->ctx.seektablelength / 4 < m->nframes) goto fail;   /* no usable seek table */
    m->seek = (uint32_t *)malloc((size_t)m->nframes * 4);
    tab = (unsigned char *)malloc((size_t)m->nframes * 4);
    if (!m->seek || !tab) { free(tab); goto fail; }
    if (NCAPE_FSEEK(f, m->ctx.seektablefilepos) || fread(tab, 4, m->nframes, f) != m->nframes) { free(tab); goto fail; }
    for (i = 0; i < m->nframes; i++) m->seek[i] = rd32(tab + 4 * (size_t)i) + junk;
    free(tab);
    for (i = 1; i < m->nframes; i++) if (m->seek[i] < m->seek[i - 1]) goto fail;
    m->scale = 1.0f / (float)(1u << (m->info.bits - 1));
    m->ctx.seektable = NULL; m->ctx.numseekpoints = 0;
    return m;
fail:
    ncape_close(m);
    return NULL;
}

void ncape_close(ncape *m)
{
    if (!m) return;
    ncape_lock();
    if (g_owner == m) g_owner = NULL;
    ncape_unlock();
    if (m->f) fclose(m->f);
    free(m->seek);
    free(m);
}

const ncape_info *ncape_get_info(const ncape *m) { return &m->info; }

uint64_t ncape_cursor(const ncape *m)
{
    if (m->frame >= m->nframes) return m->info.length;
    return (uint64_t)m->frame * m->blocksperframe + m->inframe;
}

int ncape_seek(ncape *m, uint64_t frame)
{
    if (frame >= m->info.length) { m->frame = m->nframes; m->inframe = 0; return 0; }
    m->frame = (uint32_t)(frame / m->blocksperframe);
    m->inframe = (uint32_t)(frame % m->blocksperframe);
    m->err = 0;
    return 0;
}

static uint32_t ncape_blocks(const ncape *m, uint32_t frame) { return frame == m->nframes - 1 ? m->finalblocks : m->blocksperframe; }

/* top up the shared input buffer from m's file */
static void ncape_refill(ncape *m)
{
    if (g_inlen < NCAPE_INBUF) {
        size_t n = fread(g_in + g_inlen, 1, (size_t)(NCAPE_INBUF - g_inlen), m->f);
        g_inlen += (int)n;
    }
    memset(g_in + g_inlen, 0, sizeof g_in - (size_t)g_inlen);   /* the decoder may look ahead past the end */
}

/* start libdemac at the beginning of the stream's current frame */
static int ncape_start_frame(ncape *m)
{
    uint32_t pos = m->seek[m->frame], rem = (pos - m->seek[0]) & 3, used = 0;
    int consumed = 0;
    if (NCAPE_FSEEK(m->f, pos - rem)) return -1;
    g_inlen = 0; ncape_refill(m);
    g_firstbyte = 3 - (int)rem;                       /* APE's bit stream is read in little-endian 32-bit words */
    m->ctx.currentframeblocks = (int)ncape_blocks(m, m->frame);
    init_frame_decoder(&m->ctx, g_in, &g_firstbyte, &consumed);
    used = (uint32_t)consumed;
    if (used > (uint32_t)g_inlen) return -1;
    memmove(g_in, g_in + used, (size_t)g_inlen - used); g_inlen -= (int)used;
    ncape_refill(m);
    g_owner = m; m->dframe = m->frame; m->ddone = 0;
    return 0;
}

/* decode up to n sample frames of the current frame into g_d0 / g_d1; the decoder lock is held */
static int ncape_decode(ncape *m, int n)
{
    int consumed = 0;
    if (g_owner != m || m->dframe != m->frame || m->ddone != m->inframe) {
        uint32_t skip;
        g_owner = NULL;
        if (ncape_start_frame(m)) return -1;
        for (skip = m->inframe; skip > 0;) {             /* a frame cannot be entered in the middle: decode and drop */
            int k = skip > NCAPE_CHUNK ? NCAPE_CHUNK : (int)skip;
            if (decode_chunk(&m->ctx, g_in, &g_firstbyte, &consumed, g_d0, g_d1, k) < 0) { g_owner = NULL; return -1; }
            memmove(g_in, g_in + consumed, (size_t)(g_inlen - consumed)); g_inlen -= consumed;
            ncape_refill(m);
            m->ddone += (uint32_t)k; skip -= (uint32_t)k;
        }
    }
    if (decode_chunk(&m->ctx, g_in, &g_firstbyte, &consumed, g_d0, g_d1, n) < 0) { g_owner = NULL; return -1; }
    if (consumed < 0 || consumed > g_inlen) { g_owner = NULL; return -1; }
    memmove(g_in, g_in + consumed, (size_t)(g_inlen - consumed)); g_inlen -= consumed;
    ncape_refill(m);
    m->ddone += (uint32_t)n;
    return 0;
}

uint64_t ncape_read_f32(ncape *m, float *out, uint64_t frames)
{
    uint64_t done = 0;
    const int stereo = m->info.channels == 2;
    if (m->err) return 0;
    while (done < frames && m->frame < m->nframes) {
        uint32_t left = ncape_blocks(m, m->frame) - m->inframe;
        int n = (int)(frames - done < NCAPE_CHUNK ? frames - done : NCAPE_CHUNK), i;
        if ((uint32_t)n > left) n = (int)left;
        if (n <= 0) { m->frame++; m->inframe = 0; continue; }
        ncape_lock();
        i = ncape_decode(m, n);
        if (i == 0) {
            float *o = out + done * (stereo ? 2 : 1);
            const float s = m->scale;
            for (i = 0; i < n; i++) {
                if (stereo) { *o++ = (float)g_d0[i] * s; *o++ = (float)g_d1[i] * s; }
                else *o++ = (float)g_d0[i] * s;
            }
            i = 0;
        }
        ncape_unlock();
        if (i) { m->err = 1; break; }
        m->inframe += (uint32_t)n; done += (uint64_t)n;
        if (m->inframe >= ncape_blocks(m, m->frame)) { m->frame++; m->inframe = 0; }
    }
    return done;
}
