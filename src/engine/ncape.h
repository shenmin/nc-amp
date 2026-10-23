/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * ncape - Monkey's Audio (.ape) reader for the nc-amp engine: container parsing, frame-accurate
 * seeking and float output on top of libdemac (third_party/libdemac, GPL-2.0-or-later, from
 * Rockbox). Plain C with no dependency on the rest of the engine, so it is shared by the
 * Windows and macOS builds and can be tested on its own (tests/ape).
 *
 * libdemac keeps its decoder state in static variables, so only one stream can be decoding at
 * any time. ncape lets any number of streams exist: a stream (re)starts at the beginning of its
 * current APE frame whenever another stream has used the decoder in the meantime, so opening,
 * probing and seeking never disturb a stream that is playing.
 */
#ifndef NCAPE_H
#define NCAPE_H
#include <stdio.h>
#include <stdint.h>

typedef struct ncape ncape;

typedef struct {
    uint32_t version;       /* file version * 1000, e.g. 3990 */
    uint32_t level;         /* compression level: 1000 fast ... 5000 insane */
    uint32_t channels;      /* 1 or 2 */
    uint32_t rate;          /* Hz */
    uint32_t bits;          /* bits per sample in the file: 8, 16 or 24 */
    uint64_t length;        /* sample frames (per channel) */
    uint64_t audio_bytes;   /* size of the compressed audio data in the file */
} ncape_info;

/* Parse the header only (no seek table); 0 on success. f is left open. */
int ncape_probe(FILE *f, ncape_info *info);

/* Open a stream on f. Takes ownership of f: it is closed by ncape_close() and also when
   ncape_open() fails (returns NULL). */
ncape *ncape_open(FILE *f);
void ncape_close(ncape *m);

const ncape_info *ncape_get_info(const ncape *m);
uint64_t ncape_cursor(const ncape *m);               /* current position in sample frames */
int ncape_seek(ncape *m, uint64_t frame);            /* 0 on success; frames past the end clamp to the end */
/* Decode up to `frames` sample frames as interleaved float (-1..1). Returns the number of sample
   frames written; 0 at the end of the stream or after a decoding error. */
uint64_t ncape_read_f32(ncape *m, float *out, uint64_t frames);

#endif
