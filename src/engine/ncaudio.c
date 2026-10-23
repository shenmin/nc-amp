/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * ncaudio - the nc-amp audio engine (linked into the nc-amp executable), built only from open-source parts:
 *   miniaudio (playback device; MP3/FLAC/WAV decoding via its bundled dr_libs code),
 *   stb_vorbis (Ogg Vorbis), libopus + opusfile + libogg (Opus),
 *   Windows Media Foundation / macOS AudioToolbox (M4A / AAC, decoded by the OS - no codec is bundled).
 * Plain C API used from Free Pascal (ncaudio.pas). Paths are UTF-16 (wchar_t) on Windows and
 * UTF-8 (char) on macOS (nca_char).
 */
#ifdef _WIN32
#include "win/plat.h"
#else
#include "mac/plat.h"
#endif
#include <math.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdarg.h>
#include <wchar.h>
#include <wctype.h>

#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_ENGINE
#define MA_NO_NODE_GRAPH
#define MA_NO_RESOURCE_MANAGER
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "miniaudio_libopus.h"
#include "miniaudio_libopus.c"

#undef STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define NCA_API             /* linked statically into nc-amp.exe (2.0.0+), no exports */

static int nca_ext_is(const nca_char *path, const nca_char *const *exts)
{
    const nca_char *dot = nca_strrchr(path, NCA_T('.'));
    if (!dot) return 0;
    for (; *exts; exts++) if (nca_stricmp(dot, *exts) == 0) return 1;
    return 0;
}

#ifdef _WIN32
#include "win/backend_mf.h"
#endif

#ifdef __APPLE__
#include "mac/backend_at.h"
#endif

/* ------------------------------------------------------------------ */
/* Ogg Vorbis backend: stb_vorbis in pull mode on a _wfopen()ed file    */
/* (exact length + sample-accurate seeking, Unicode paths)             */
/* ------------------------------------------------------------------ */
typedef struct {
    ma_data_source_base ds;
    stb_vorbis *v;
    ma_uint32 channels, rate;
    ma_uint64 length, cursor;
} nca_vorbis;

static ma_result nca_vb_read(ma_data_source *pDS, void *out, ma_uint64 frameCount, ma_uint64 *pRead)
{
    nca_vorbis *m = (nca_vorbis*)pDS; ma_uint64 done = 0; float tmp[4096];
    while (done < frameCount) {
        int want = (int)((frameCount - done) > 2048 ? 2048 : (frameCount - done)), got;
        if (want * (int)m->channels > 4096) want = 4096 / (int)m->channels;
        got = out ? stb_vorbis_get_samples_float_interleaved(m->v, (int)m->channels, (float*)out + done * m->channels, want * (int)m->channels)
                  : stb_vorbis_get_samples_float_interleaved(m->v, (int)m->channels, tmp, want * (int)m->channels);
        if (got <= 0) break;
        done += (ma_uint64)got;
    }
    m->cursor += done;
    if (pRead) *pRead = done;
    return (done == 0 && frameCount > 0) ? MA_AT_END : MA_SUCCESS;
}
static ma_result nca_vb_seek(ma_data_source *pDS, ma_uint64 frame)
{
    nca_vorbis *m = (nca_vorbis*)pDS;
    if (!stb_vorbis_seek(m->v, (unsigned int)frame)) { if (frame != 0 || !stb_vorbis_seek_start(m->v)) return MA_ERROR; }
    m->cursor = frame;
    return MA_SUCCESS;
}
static ma_result nca_vb_format(ma_data_source *pDS, ma_format *f, ma_uint32 *ch, ma_uint32 *sr, ma_channel *map, size_t cap)
{
    nca_vorbis *m = (nca_vorbis*)pDS;
    if (f) *f = ma_format_f32;
    if (ch) *ch = m->channels;
    if (sr) *sr = m->rate;
    if (map) ma_channel_map_init_standard(ma_standard_channel_map_vorbis, map, cap, m->channels);
    return MA_SUCCESS;
}
static ma_result nca_vb_cursor(ma_data_source *pDS, ma_uint64 *c) { *c = ((nca_vorbis*)pDS)->cursor; return MA_SUCCESS; }
static ma_result nca_vb_length(ma_data_source *pDS, ma_uint64 *l) { *l = ((nca_vorbis*)pDS)->length; return MA_SUCCESS; }
static ma_data_source_vtable g_nca_vb_ds_vtable = { nca_vb_read, nca_vb_seek, nca_vb_format, nca_vb_cursor, nca_vb_length, NULL, 0 };

static const nca_char *const g_vbExts[] = { NCA_T(".ogg"), NCA_T(".oga"), NULL };

static ma_result nca_vb_init_file_w(void *ud, const nca_char *path, const ma_decoding_backend_config *cfg,
                                    const ma_allocation_callbacks *alloc, ma_data_source **ppDS)
{
    nca_vorbis *m; FILE *f; int err = 0; stb_vorbis_info vi;
    (void)ud; (void)cfg; (void)alloc;
    if (!nca_ext_is(path, g_vbExts)) return MA_INVALID_FILE;
    f = nca_fopen_rb(path);
    if (!f) return MA_INVALID_FILE;
    m = (nca_vorbis*)calloc(1, sizeof(*m));
    if (!m) { fclose(f); return MA_OUT_OF_MEMORY; }
    m->v = stb_vorbis_open_file(f, 1, &err, NULL);       /* closes f on failure/free */
    if (!m->v) { free(m); return MA_INVALID_FILE; }      /* not Vorbis (e.g. Opus in .ogg) */
    vi = stb_vorbis_get_info(m->v);
    m->channels = (ma_uint32)vi.channels; m->rate = vi.sample_rate;
    m->length = stb_vorbis_stream_length_in_samples(m->v);
    {
        ma_data_source_config dc = ma_data_source_config_init();
        dc.vtable = &g_nca_vb_ds_vtable;
        if (ma_data_source_init(&dc, &m->ds) != MA_SUCCESS) { stb_vorbis_close(m->v); free(m); return MA_ERROR; }
    }
    *ppDS = (ma_data_source*)m;
    return MA_SUCCESS;
}
static void nca_vb_uninit(void *ud, ma_data_source *pDS, const ma_allocation_callbacks *alloc)
{
    nca_vorbis *m = (nca_vorbis*)pDS; (void)ud; (void)alloc;
    ma_data_source_uninit(&m->ds);
    stb_vorbis_close(m->v);
    free(m);
}
#ifdef _WIN32
static ma_decoding_backend_vtable g_nca_vb_backend = { NULL, NULL, nca_vb_init_file_w, NULL, nca_vb_uninit };
#else
static ma_decoding_backend_vtable g_nca_vb_backend = { NULL, nca_vb_init_file_w, NULL, NULL, nca_vb_uninit };   /* (the "_w" function takes the UTF-8 path here) */
#endif

/* ------------------------------------------------------------------ */
/* player                                                              */
/* ------------------------------------------------------------------ */
typedef struct {
    int sample_rate, channels;   /* of the source */
    double length;               /* seconds, <= 0 unknown */
    int bitrate;                 /* kbps (average) */
    char codec[16];
} nca_info;

enum { NCA_STOPPED = 0, NCA_PLAYING = 1, NCA_PAUSED = 2, NCA_ENDED = 3 };

#define RING 4096
static ma_device g_dev; static int g_devOk = 0, g_lockOk = 0;
/* decoder / play state lock. Held only for short decoder work and pointer swaps - never across a
   device lifecycle call - and the audio callback only tries it (see nca_cb_lock) */
static CRITICAL_SECTION g_cs;
static volatile unsigned g_decGen = 0;        /* bumped by nca_open / nca_close: a rebuild in flight is stale */
static volatile ma_uint32 g_devRate = 0;      /* sample rate of the open device, 0 = none (set by the engine thread) */
static volatile LONG g_cbBusy = 0;            /* callbacks that found the lock busy and played silence */
static ma_decoder *g_dec = NULL;
static volatile int g_state = NCA_STOPPED;
/* track length in output (device-rate) frames, measured ONCE when the decoder is built; 0 = unknown.
   Never ask the decoder for its length while it plays: for an MP3 without a Xing/Info header
   dr_mp3 answers by rescanning the whole file and then seeking back to where it was. In the last
   few frames of a file that seek-back fails (after a seek-table jump minimp3 must re-sync on
   several consecutive frame headers, and a trailing APE/ID3v1 tag leaves too few), and the failed
   seek has already reset dr_mp3's frame counter to 0. The next length query before any audio is
   read then "restores" position 0 - successfully - so the song starts over while the decoder's
   cursor, our playback position, keeps counting: the time runs past the duration and the end is
   never reached (1.7.6 queried the length several times per repaint). */
static ma_uint64 g_lenFrames = 0;
static volatile int g_endReason = 0;   /* 1 = decoder EOF, 2 = known length reached, 3 = seek to the end (logged by nca_poll) */
static volatile double g_endPos = 0;
static volatile float g_vol = 1.0f, g_pan = 0.0f;
static float g_ring[RING]; static volatile LONG g_ringPos = 0;
static char g_err[256] = "";
static ma_decoding_backend_vtable *g_backends[3];
static volatile float g_peakOut = 0; static volatile LONG g_cbCount = 0, g_cbFrames = 0, g_cbTotal = 0;
static volatile int g_reopening = 0, g_devInited = 0;
static volatile int g_needRestart = 0, g_needDescribe = 0, g_shuttingDown = 0;
static nca_char g_path[NCA_MAXPATH];
static void nca_copy_path(nca_char *dst, const nca_char *src) { size_t i; for (i = 0; i < NCA_MAXPATH - 1 && src[i]; i++) dst[i] = src[i]; dst[i] = 0; }
static WCHAR g_openId[512];   /* default render endpoint id when the device was opened ("" = none / unknown) */
/* auto-pause on a real output-device change (1.7.8) */
#define NCA_BURST_MS 3000           /* changes this soon after an auto-pause belong to it (BT HFP -> A2DP) */
static ULONGLONG g_lastAutoPause = 0;  /* when the last auto-pause happened; only a new auto-pause moves it */
static volatile LONG g_autoPaused = 0;
static char g_autoWhy[600];
/* NCAMP_TEST_DEVICE hooks: simulated default endpoint (g_testDefOn), forced device rate, no device until */
static int g_testMode = -1, g_testDefOn = 0, g_testRate = 0, g_testStuck = 0;
static volatile DWORD g_testHangMs = 0;   /* test "hang": the next device close blocks this long in the "driver" */
static WCHAR g_testDef[64];
static ULONGLONG g_testNoDevUntil = 0;
static volatile int g_testFailWrite = 0;   /* next device write fails: the worker stops on its own */
static HANDLE g_testRouteEv = NULL;      /* NCAMP_TEST_ROUTING: wakes nca_test_router on default changes */
static DWORD WINAPI nca_test_router(LPVOID unused);
static void nca_test_init(void);
static void nca_test_device_opened(void);
/* Device lifecycle (2.0.1): ma_device_init / start / stop / uninit run only on the engine thread
   (nca_engine_thread), never on the UI thread and never from miniaudio's callbacks or
   notifications, which only set flags. miniaudio's own automatic stream routing is off: on
   WASAPI it stopped, re-initialised and restarted the device from its COM notification thread,
   concurrently with our reopen of the same ma_device - see nca_device_close. */
static DWORD g_ownerThread = 0;
static int g_autoRouting = 0;           /* miniaudio's automatic stream routing on (never, since 2.0.1) */
/* the engine thread (2.0.1): every device lifecycle call and the endpoint polling run here, so the
   UI thread never waits for a device - a device operation that hangs in the driver cannot freeze
   the window. The UI only posts requests (flags), reads state and logs. */
static HANDLE g_engThread = NULL, g_engWake = NULL, g_engReady = NULL;
static volatile LONG g_engQuit = 0;
static volatile ULONGLONG g_opSince = 0;      /* start of the device operation in progress (watchdog), 0 = none */
static const char *volatile g_opName = "";
static void nca_op(const char *name) { g_opName = name; g_opSince = name ? GetTickCount64() : 0; }
static char g_log[16384]; static CRITICAL_SECTION g_logCs; static int g_logCsOk = 0;

/* The audio callback must never wait for long: if the lock stays busy for ~5 ms (a seek in a slow
   file, say) this period is played as silence instead of stalling miniaudio's worker thread */
static int nca_cb_lock(void)
{
    int i;
    for (i = 0; i < 64; i++) { if (TryEnterCriticalSection(&g_cs)) return 1; SwitchToThread(); }
    for (i = 0; i < 4; i++) { Sleep(1); if (TryEnterCriticalSection(&g_cs)) return 1; }
    return 0;
}

static void cb(ma_device *dev, void *out, const void *in, ma_uint32 frames)
{
    float *o = (float*)out; ma_uint64 got = 0; ma_uint32 i; float gl, gr, v;
    (void)in; (void)dev;
    if (!nca_cb_lock()) { InterlockedIncrement(&g_cbBusy); memset(o, 0, (size_t)frames * 2 * sizeof(float)); return; }
    if (g_dec && g_state == NCA_PLAYING) {
        ma_uint64 want = frames, cur = 0;
        if (g_lenFrames) {        /* never play past the known length */
            ma_decoder_get_cursor_in_pcm_frames(g_dec, &cur);
            want = cur >= g_lenFrames ? 0 : (g_lenFrames - cur < frames ? g_lenFrames - cur : frames);
        }
        if (want) ma_decoder_read_pcm_frames(g_dec, o, want, &got);
        if (got < frames) {
            g_state = NCA_ENDED;
            g_endReason = (got < want || !g_lenFrames) ? 1 : 2;
            g_endPos = g_dec->outputSampleRate ? (double)(cur + got) / g_dec->outputSampleRate : 0;
        }
    }
    LeaveCriticalSection(&g_cs);
    if (got < frames) memset(o + got * 2, 0, (size_t)(frames - got) * 2 * sizeof(float));
    {   /* spectrum tap (pre-volume, mono) */
        LONG p = g_ringPos;
        for (i = 0; i < (ma_uint32)got; i++) { g_ring[p] = 0.5f * (o[i*2] + o[i*2+1]); p = (p + 1) & (RING - 1); }
        InterlockedExchange(&g_ringPos, p);
    }
    v = g_vol;
    gl = v * (g_pan > 0 ? 1.0f - g_pan : 1.0f);
    gr = v * (g_pan < 0 ? 1.0f + g_pan : 1.0f);
    {   /* de-zipper: ramp linearly from the previous gains to the new ones across this
           buffer, so volume / balance can change on every mouse move without clicks */
        static float curL = -1, curR = -1;
        float dl, dr, n = (float)(got ? got : 1);
        if (curL < 0) { curL = gl; curR = gr; }
        dl = (gl - curL) / n; dr = (gr - curR) / n;
        for (i = 0; i < (ma_uint32)got; i++) {
            curL += dl; curR += dr;
            o[i*2] *= curL; o[i*2+1] *= curR;
        }
        if (got) { curL = gl; curR = gr; }
    }
    {   /* diagnostics: peak of what is actually handed to the device */
        float pk = 0, a; ma_uint32 n = frames * 2;
        for (i = 0; i < n; i++) { a = o[i] < 0 ? -o[i] : o[i]; if (a > pk) pk = a; }
        if (pk > g_peakOut) g_peakOut = pk;
        g_cbCount++; g_cbFrames += frames; g_cbTotal++;
    }
}

static void nca_log(const char *fmt, ...)
{
    char line[512]; va_list ap; size_t n;
    if (!g_logCsOk) { InitializeCriticalSection(&g_logCs); g_logCsOk = 1; }
    va_start(ap, fmt); vsnprintf(line, sizeof line, fmt, ap); va_end(ap);
    EnterCriticalSection(&g_logCs);
    n = strlen(g_log);
    if (n + strlen(line) + 2 < sizeof g_log) { strcat(g_log, line); strcat(g_log, "\n"); }
    LeaveCriticalSection(&g_logCs);
}

/* returns (and clears) the engine's pending log lines */
NCA_API int nca_take_log(char *buf, int cap)
{
    int n;
    if (!buf || cap <= 0) return 0;
    EnterCriticalSection(&g_logCs);
    n = (int)strlen(g_log); if (n >= cap) n = cap - 1;
    memcpy(buf, g_log, (size_t)n); buf[n] = 0; g_log[0] = 0;
    LeaveCriticalSection(&g_logCs);
    return n;
}

/* peak (0..1+) of the samples written to the device since the last call, callback count */
NCA_API float nca_take_peak(int *callbacks, int *frames)
{
    float p = g_peakOut; g_peakOut = 0;
    if (callbacks) *callbacks = (int)g_cbCount;
    if (frames) *frames = (int)g_cbFrames;
    g_cbCount = 0; g_cbFrames = 0;
    return p;
}

static void nca_notify(const ma_device_notification *n)
{
    static const char *names[] = { "started", "stopped", "rerouted", "interruption_began", "interruption_ended", "unlocked" };
    int t = (int)n->type;
    nca_log("device notification: %s", (t >= 0 && t < 6) ? names[t] : "?");
    if (g_reopening || g_shuttingDown) return;
    if (n->type == ma_device_notification_type_stopped) g_needRestart = 1;
    if (n->type == ma_device_notification_type_rerouted) g_needDescribe = 1;
    if (n->type == ma_device_notification_type_interruption_ended || n->type == ma_device_notification_type_unlocked) g_needRestart = 1;
}

static void nca_describe(void)
{
    ma_device_info *pb = NULL; ma_uint32 npb = 0, i;
    nca_log("backend=%s", ma_get_backend_name(g_dev.pContext->backend));
    nca_log("device='%s' state=%d", g_dev.playback.name, (int)ma_device_get_state(&g_dev));
    nca_log("client: %s %uch %uHz | device(internal): %s %uch %uHz period=%u frames x %u, shareMode=%s",
        ma_get_format_name(g_dev.playback.format), g_dev.playback.channels, g_dev.sampleRate,
        ma_get_format_name(g_dev.playback.internalFormat), g_dev.playback.internalChannels, g_dev.playback.internalSampleRate,
        g_dev.playback.internalPeriodSizeInFrames, g_dev.playback.internalPeriods,
        g_dev.playback.shareMode == ma_share_mode_exclusive ? "exclusive" : "shared");
    {
        char cm[256]; ma_channel_map_to_string(g_dev.playback.internalChannelMap, g_dev.playback.internalChannels, cm, sizeof cm);
        nca_log("device channel map: %s", cm);
    }
    if (ma_context_get_devices(g_dev.pContext, &pb, &npb, NULL, NULL) == MA_SUCCESS)
        for (i = 0; i < npb; i++) nca_log("  playback endpoint %u: '%s'%s", i, pb[i].name, pb[i].isDefault ? " [default]" : "");
    { float mv = -1; ma_device_get_master_volume(&g_dev, &mv); nca_log("volume=%.3f pan=%.3f masterVolume=%.3f", g_vol, g_pan, mv); }
}

#ifdef _WIN32
NCA_API const char *nca_version(void) { return "miniaudio " MA_VERSION_STRING ", stb_vorbis 1.22, opusfile 0.12 / libopus 1.5.2, Media Foundation (AAC)"; }
#else
NCA_API const char *nca_version(void) { return "miniaudio " MA_VERSION_STRING ", stb_vorbis 1.22, opusfile 0.12 / libopus 1.5.2, AudioToolbox (AAC)"; }
#endif
NCA_API const char *nca_error(void) { return g_err; }

static void nca_setup(void)
{
    if (!g_logCsOk) { InitializeCriticalSection(&g_logCs); g_logCsOk = 1; }
    if (!g_lockOk) { InitializeCriticalSection(&g_cs); g_lockOk = 1; }
    g_backends[0] = &g_nca_vb_backend;
    g_backends[1] = ma_decoding_backend_libopus;
#ifdef _WIN32
    g_backends[2] = &g_nca_mf_backend;
#else
    g_backends[2] = &g_nca_at_backend;
#endif
}

/* open + start the playback device on the *current default* endpoint (pDeviceID = NULL,
   WASAPI first). miniaudio's automatic stream routing is off; nca_poll follows the default
   endpoint itself and reopens the device. */
static int nca_default_endpoint(WCHAR *id, int cap, DWORD *state);

static int nca_device_open(void)
{
    ma_device_config dc = ma_device_config_init(ma_device_type_playback);
    ma_result r;
    if (GetTickCount64() < g_testNoDevUntil) {   /* NCAMP_TEST_DEVICE=nodev|remove */
        snprintf(g_err, sizeof g_err, "no audio output device (TEST)"); nca_log("%s", g_err); return 0;
    }
    dc.playback.format = ma_format_f32;
    dc.playback.channels = 2;
    dc.sampleRate = g_testRate;         /* 0 = device native rate */
    dc.dataCallback = cb;
    dc.notificationCallback = nca_notify;
    dc.performanceProfile = ma_performance_profile_conservative;
    dc.wasapi.noAutoStreamRouting = MA_TRUE;
    g_autoRouting = !dc.wasapi.noAutoStreamRouting;
#ifdef __APPLE__
    /* An explicit device id (the UID of the current default output, see nca_default_endpoint) keeps
       miniaudio's CoreAudio backend from following default-device changes itself, from CoreAudio's
       notification thread; the engine thread polls the default and reopens (like on Windows). */
    {
        static ma_device_id did; WCHAR cur[512]; DWORD st = 0; char u8[256]; size_t k;
        if (!g_testDefOn && nca_default_endpoint(cur, 512, &st)) {
            for (k = 0; k < sizeof u8 - 1 && cur[k]; k++) u8[k] = (char)cur[k];
            u8[k] = 0;
            memset(&did, 0, sizeof did); strncpy(did.coreaudio, u8, sizeof did.coreaudio - 1);
            dc.playback.pDeviceID = &did;
        }
    }
#endif
    r = ma_device_init(NULL, &dc, &g_dev);
    if (r != MA_SUCCESS) { snprintf(g_err, sizeof g_err, "no audio output device (%s)", ma_result_description(r)); nca_log("%s", g_err); return 0; }
    nca_test_device_opened();
    r = ma_device_start(&g_dev);
    if (r != MA_SUCCESS) { ma_device_uninit(&g_dev); snprintf(g_err, sizeof g_err, "cannot start audio device (%s)", ma_result_description(r)); nca_log("%s", g_err); return 0; }
    return 1;
}

/* Tear the playback device down (owner thread only). 1 = closed, 0 = not now, retry later.
   When a device fails (WASAPI: device invalidated, e.g. earbuds gone) miniaudio's worker thread
   leaves its loop on its own, posts the "stopped" notification and only then sets the state to
   stopped (ma_worker_thread). ma_device_uninit() sets the state to uninitialized without taking
   any lock: called in that window, the worker overwrites "uninitialized" with "stopped", wakes up
   on uninit's signal and fails MA_ASSERT(ma_device_get_state(pDevice) == ma_device_state_starting)
   - or, with assertions off, starts a device that is being destroyed while uninit waits for the
   thread. ma_device_stop() takes the device's start/stop lock and waits until the worker has
   really stopped, so the uninit after it is safe. A device caught starting or stopping (which
   only another thread could cause) is left alone and closed on a later poll. */
static int nca_device_close(int shutdown)
{
    ma_device_state st;
    if (!g_devInited) return 1;
    if (g_ownerThread && GetCurrentThreadId() != g_ownerThread) { nca_log("device close from a foreign thread refused"); return 0; }
    st = ma_device_get_state(&g_dev);
    if (!shutdown && (st == ma_device_state_starting || st == ma_device_state_stopping)) {
        nca_log("device busy (state %d), closing it later", (int)st);
        return 0;
    }
    if (g_testHangMs) { DWORD ms = g_testHangMs; g_testHangMs = 0; nca_log("TEST: device stop blocks for %lu ms", (unsigned long)ms); Sleep(ms); }
    ma_device_stop(&g_dev);
    ma_device_uninit(&g_dev);
    g_devInited = 0;
    return 1;
}

static void nca_remember_endpoint(void);
static int nca_default_endpoint(WCHAR *id, int cap, DWORD *state);

static DWORD WINAPI nca_engine_thread(LPVOID unused);

/* starts the engine thread and waits (at most 3 s) for its first attempt to open the device:
   1 = a device is open. Without one, the engine thread keeps retrying. */
NCA_API int nca_init(void)
{
    nca_setup();
    nca_test_init();
    if (g_engThread) return g_devOk;
    g_engWake = CreateEventA(NULL, FALSE, FALSE, NULL);
    g_engReady = CreateEventA(NULL, TRUE, FALSE, NULL);
    g_engThread = CreateThread(NULL, 0, nca_engine_thread, NULL, 0, NULL);
    if (!g_engThread) { snprintf(g_err, sizeof g_err, "cannot start the audio engine thread"); return 0; }
    if (WaitForSingleObject(g_engReady, 3000) != WAIT_OBJECT_0) {
        nca_log("audio device still opening after 3 s, continuing (the engine thread keeps going)");
        snprintf(g_err, sizeof g_err, "audio device not ready yet");
        return 0;
    }
    return g_devOk;
}

NCA_API int nca_device_rate(void) { return (int)g_devRate; }

static ma_decoder_config nca_cfg(int forPlayback)
{
    ma_decoder_config c = ma_decoder_config_init(forPlayback ? ma_format_f32 : ma_format_unknown,
                                                 forPlayback ? 2 : 0, forPlayback ? g_devRate : 0);
    c.ppCustomBackendVTables = g_backends;
    c.customBackendCount = 3;
    c.seekPointCount = forPlayback ? 4096 : 0;      /* fast, accurate MP3 seeking */
    c.resampling.algorithm = ma_resample_algorithm_linear;
    c.resampling.linear.lpfOrder = 8;
    return c;
}

/* ---- bitrate: average over the *audio payload* only (tags, cover art and metadata
   blocks excluded); for MP3 the frame-header bitrate is reported for CBR files ---- */
static ma_uint64 rd_be32(const unsigned char *b) { return ((ma_uint64)b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]; }
static ma_uint64 rd_le32(const unsigned char *b) { return ((ma_uint64)b[3] << 24) | (b[2] << 16) | (b[1] << 8) | b[0]; }

static int nca_read_at(FILE *f, ma_int64 pos, void *buf, int n)
{
    if (pos < 0 || nca_fseek64(f, pos, SEEK_SET) != 0) return 0;
    return (int)fread(buf, 1, (size_t)n, f);
}

/* MPEG audio frame header bitrate in kbps (0 = not a valid header) */
static int nca_mp3_hdr_kbps(const unsigned char *h, int *isV1, int *mono)
{
    static const short v1l3[16] = {0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0};
    static const short v1l2[16] = {0,32,48,56,64,80,96,112,128,160,192,224,256,320,384,0};
    static const short v1l1[16] = {0,32,64,96,128,160,192,224,256,288,320,352,384,416,448,0};
    static const short v2l1[16] = {0,32,48,56,64,80,96,112,128,144,160,176,192,224,256,0};
    static const short v2l23[16] = {0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0};
    int ver, layer, bi;
    if (h[0] != 0xFF || (h[1] & 0xE0) != 0xE0) return 0;
    ver = (h[1] >> 3) & 3; layer = (h[1] >> 1) & 3; bi = h[2] >> 4;
    if (ver == 1 || layer == 0 || bi == 0 || bi == 15 || ((h[2] >> 2) & 3) == 3) return 0;
    *isV1 = ver == 3; *mono = (h[3] >> 6) == 3;
    if (ver == 3) return layer == 1 ? v1l3[bi] : layer == 2 ? v1l2[bi] : v1l1[bi];
    return layer == 3 ? v2l1[bi] : v2l23[bi];
}

static int nca_calc_bitrate(const nca_char *path, double seconds)
{
    FILE *f; ma_int64 size, start = 0, end; unsigned char b[64];
    const nca_char *dot = nca_strrchr(path, NCA_T('.'));
    int hdrKbps = 0, cbrKnown = 0, vbrKnown = 0, kbps;
    if (seconds <= 0) return 0;
    f = nca_fopen_rb(path);
    if (!f) return 0;
    nca_fseek64(f, 0, SEEK_END); size = nca_ftell64(f); end = size;
    /* leading ID3v2 (any format may carry one) */
    if (nca_read_at(f, 0, b, 10) == 10 && b[0] == 'I' && b[1] == 'D' && b[2] == '3')
        start = 10 + (((ma_int64)(b[6] & 0x7F) << 21) | ((b[7] & 0x7F) << 14) | ((b[8] & 0x7F) << 7) | (b[9] & 0x7F)) + ((b[5] & 0x10) ? 10 : 0);
    /* trailing ID3v1 and APEv2 */
    if (end - 128 > start && nca_read_at(f, end - 128, b, 3) == 3 && b[0] == 'T' && b[1] == 'A' && b[2] == 'G') end -= 128;
    if (end - 32 > start && nca_read_at(f, end - 32, b, 32) == 32 && memcmp(b, "APETAGEX", 8) == 0) {
        ma_int64 t = (ma_int64)rd_le32(b + 12) + ((b[23] & 0x80) ? 32 : 0);
        if (t > 0 && end - t > start) end -= t;
    }
    if (dot && nca_stricmp(dot, NCA_T(".flac")) == 0) {
        /* skip all metadata blocks (pictures, padding, seek tables...) */
        ma_int64 p = start;
        if (nca_read_at(f, p, b, 4) == 4 && memcmp(b, "fLaC", 4) == 0) {
            p += 4;
            for (;;) {
                if (nca_read_at(f, p, b, 4) != 4) break;
                p += 4 + (((ma_int64)b[1] << 16) | (b[2] << 8) | b[3]);
                if (b[0] & 0x80) break;
            }
            if (p < end) start = p;
        }
    } else if (dot && (nca_stricmp(dot, NCA_T(".ogg")) == 0 || nca_stricmp(dot, NCA_T(".oga")) == 0 || nca_stricmp(dot, NCA_T(".opus")) == 0)) {
        /* header pages (granule 0: id + comment headers, maybe with cover art) */
        ma_int64 p = start; int pages = 0;
        while (pages++ < 4096 && nca_read_at(f, p, b, 27 + 0) == 27 && memcmp(b, "OggS", 4) == 0) {
            unsigned char seg[255]; int nseg = b[26], i; ma_int64 body = 0;
            ma_uint64 gran = rd_le32(b + 6) | (rd_le32(b + 10) << 32);
            if (gran != 0 && gran != (ma_uint64)-1) { start = p; break; }
            if (nca_read_at(f, p + 27, seg, nseg) != nseg) break;
            for (i = 0; i < nseg; i++) body += seg[i];
            p += 27 + nseg + body;
        }
    } else if (dot && (nca_stricmp(dot, NCA_T(".m4a")) == 0 || nca_stricmp(dot, NCA_T(".mp4")) == 0 || nca_stricmp(dot, NCA_T(".m4b")) == 0)) {
        /* sum of top-level 'mdat' atoms */
        ma_int64 p = 0, mdat = 0;
        while (p + 8 <= size && nca_read_at(f, p, b, 16) >= 8) {
            ma_int64 sz = (ma_int64)rd_be32(b);
            if (sz == 1) sz = (ma_int64)((rd_be32(b + 8) << 32) | rd_be32(b + 12));
            else if (sz == 0) sz = size - p;
            if (sz < 8) break;
            if (memcmp(b + 4, "mdat", 4) == 0) mdat += sz;
            p += sz;
        }
        if (mdat > 0) { start = 0; end = mdat; }
    } else if (dot && (nca_stricmp(dot, NCA_T(".mp3")) == 0 || nca_stricmp(dot, NCA_T(".mp2")) == 0)) {
        /* first frame header (resync over junk) + Xing / Info / VBRI tag */
        unsigned char buf[4096]; int n = nca_read_at(f, start, buf, sizeof buf), i;
        for (i = 0; i + 4 <= n; i++) {
            int v1 = 0, mono = 0, k = nca_mp3_hdr_kbps(buf + i, &v1, &mono);
            if (k) {
                int xo = i + 4 + (v1 ? (mono ? 17 : 32) : (mono ? 9 : 17));
                hdrKbps = k;
                if (xo + 4 <= n && memcmp(buf + xo, "Info", 4) == 0) cbrKnown = 1;
                else if (xo + 4 <= n && memcmp(buf + xo, "Xing", 4) == 0) vbrKnown = 1;
                else if (i + 40 <= n && memcmp(buf + i + 36, "VBRI", 4) == 0) vbrKnown = 1;
                break;
            }
        }
    }
    fclose(f);
    if (end <= start) return 0;
    kbps = (int)((double)(end - start) * 8.0 / seconds / 1000.0 + 0.5);
    if (hdrKbps && !vbrKnown && (cbrKnown || abs(kbps - hdrKbps) * 50 <= hdrKbps)) kbps = hdrKbps;  /* CBR */
    return kbps;
}

/* length of the decoder's source in its native frames (+ native rate); one scan for header-less MP3 */
static ma_uint64 nca_src_len(ma_decoder *d, ma_uint32 *srOut)
{
    ma_format f; ma_uint32 ch = 0, sr = 0; ma_uint64 len = 0;
    if (d->pBackend) ma_data_source_get_data_format(d->pBackend, &f, &ch, &sr, NULL, 0);
    if (!d->pBackend || ma_data_source_get_length_in_pcm_frames(d->pBackend, &len) != MA_SUCCESS) len = 0;
    if (srOut) *srOut = sr;
    return len;
}

/* the same length in output frames (what the decoder cursor counts) */
static ma_uint64 nca_out_len(ma_decoder *d, ma_uint64 srcLen, ma_uint32 sr)
{
    if (!srcLen || !sr || !d->outputSampleRate) return 0;
    if (sr == d->outputSampleRate) return srcLen;
    return ma_calculate_frame_count_after_resampling(d->outputSampleRate, sr, srcLen);
}

static void nca_fill_info(ma_decoder *d, const nca_char *path, nca_info *info, ma_uint64 len)
{
    ma_format f; ma_uint32 ch = 0, sr = 0;
    const nca_char *dot;
    memset(info, 0, sizeof(*info));
    if (d->pBackend) ma_data_source_get_data_format(d->pBackend, &f, &ch, &sr, NULL, 0);
    info->channels = (int)ch; info->sample_rate = (int)sr;
    if (sr && len) info->length = (double)len / sr;
    else info->length = -1;
    info->bitrate = nca_calc_bitrate(path, info->length);
    dot = nca_strrchr(path, NCA_T('.'));
    if (dot) { int i; for (i = 0; i < 15 && dot[i + 1]; i++) info->codec[i] = (char)toupper((unsigned char)dot[i + 1]); }
}

/* open a file for playback; replaces the current one. 1 = ok */
NCA_API int nca_open(const nca_char *path, nca_info *info)
{
    ma_decoder *d, *old; ma_decoder_config c; ma_result r;
    nca_setup();
    d = (ma_decoder*)malloc(sizeof(ma_decoder));
    if (!d) return 0;
    c = nca_cfg(1);
    r = nca_decoder_init_file(path, &c, d);
    if (r != MA_SUCCESS) { free(d); snprintf(g_err, sizeof g_err, "cannot decode (%s)", ma_result_description(r)); return 0; }
    {
        ma_uint32 sr = 0; ma_uint64 srcLen = nca_src_len(d, &sr), outLen = nca_out_len(d, srcLen, sr);
        ma_decoder_seek_to_pcm_frame(d, 0);   /* the length scan must leave the stream at the start */
        if (info) nca_fill_info(d, path, info, srcLen);
        EnterCriticalSection(&g_cs);
        g_lenFrames = outLen; g_endReason = 0;
    }
    old = g_dec; g_dec = d; g_state = NCA_STOPPED; g_decGen++;
    nca_copy_path(g_path, path);

    LeaveCriticalSection(&g_cs);
    if (old) { ma_decoder_uninit(old); free(old); }
    return 1;
}

NCA_API void nca_close(void)
{
    ma_decoder *old;
    if (!g_lockOk) return;
    EnterCriticalSection(&g_cs); old = g_dec; g_dec = NULL; g_state = NCA_STOPPED; g_lenFrames = 0; g_decGen++; LeaveCriticalSection(&g_cs);
    if (old) { ma_decoder_uninit(old); free(old); }
}

NCA_API void nca_play(void)  { if (!g_lockOk) return; EnterCriticalSection(&g_cs); if (g_dec) g_state = NCA_PLAYING; LeaveCriticalSection(&g_cs); }
NCA_API void nca_pause(void) { if (!g_lockOk) return; EnterCriticalSection(&g_cs); if (g_state == NCA_PLAYING) g_state = NCA_PAUSED; LeaveCriticalSection(&g_cs); }
NCA_API void nca_stop(void)
{
    if (!g_lockOk) return;
    EnterCriticalSection(&g_cs);
    if (g_dec) { g_state = NCA_STOPPED; ma_decoder_seek_to_pcm_frame(g_dec, 0); }
    LeaveCriticalSection(&g_cs);
}
NCA_API int nca_state(void) { return g_state; }

NCA_API double nca_get_pos(void)
{
    ma_uint64 c = 0; double r = 0;
    if (!g_lockOk) return 0;
    EnterCriticalSection(&g_cs);
    if (g_dec && ma_decoder_get_cursor_in_pcm_frames(g_dec, &c) == MA_SUCCESS && g_dec->outputSampleRate) {
        if (g_lenFrames && c > g_lenFrames) c = g_lenFrames;   /* the position never exceeds the length */
        r = (double)c / g_dec->outputSampleRate;
    }
    LeaveCriticalSection(&g_cs);
    return r;
}

/* cached at open / rebuild: no decoder call (see g_lenFrames) */
NCA_API double nca_get_len(void)
{
    double r = 0;
    if (!g_lockOk) return 0;
    EnterCriticalSection(&g_cs);
    if (g_dec && g_lenFrames && g_dec->outputSampleRate) r = (double)g_lenFrames / g_dec->outputSampleRate;
    LeaveCriticalSection(&g_cs);
    return r;
}

NCA_API int nca_seek(double sec)
{
    int ok = 0;
    if (!g_lockOk) return 0;
    if (sec < 0) sec = 0;
    EnterCriticalSection(&g_cs);
    if (g_dec) {
        ma_uint64 t = (ma_uint64)(sec * g_dec->outputSampleRate), was = 0;
        if (g_lenFrames && t > g_lenFrames) t = g_lenFrames;
        ma_decoder_get_cursor_in_pcm_frames(g_dec, &was);
        ok = ma_decoder_seek_to_pcm_frame(g_dec, t) == MA_SUCCESS;
        if (g_state == NCA_ENDED) g_state = NCA_PLAYING;
        if (!ok) {
            /* dr_mp3 cannot seek into the last few frames of some files (after a seek it must
               re-sync on several consecutive frame headers, and near the end there are too few).
               A failed seek leaves the stream somewhere else: treat a seek to the end as the end,
               otherwise go back to where we were so stream and cursor stay in step */
            if (g_lenFrames && t + g_dec->outputSampleRate >= g_lenFrames) {
                if (g_state == NCA_PLAYING) { g_state = NCA_ENDED; g_endReason = 3; g_endPos = (double)t / g_dec->outputSampleRate; }
            } else ma_decoder_seek_to_pcm_frame(g_dec, was);
        }
    }
    LeaveCriticalSection(&g_cs);
    return ok;
}

NCA_API void nca_set_volume(float v) { g_vol = v < 0 ? 0 : (v > 1 ? 1 : v); nca_log("set_volume(%.3f) -> %.3f", v, g_vol); }
NCA_API void nca_set_pan(float p)    { g_pan = p < -1 ? -1 : (p > 1 ? 1 : p); nca_log("set_pan(%.3f) -> %.3f", p, g_pan); }

/* 512 magnitude bins of a 1024-point Hann-windowed FFT of the most recent output
   (same layout as classic "FFT1024" visualisation data). 1 = ok */
NCA_API int nca_get_fft(float *out512)
{
    static float re[1024], im[1024], win[1024]; static int winOk = 0;
    int i, j, k, n = 1024, len, half; LONG p;
    if (!winOk) { for (i = 0; i < n; i++) win[i] = 0.5f - 0.5f * cosf(2.0f * 3.14159265f * i / (n - 1)); winOk = 1; }
    p = g_ringPos;
    for (i = 0; i < n; i++) { re[i] = g_ring[(p - n + i) & (RING - 1)] * win[i]; im[i] = 0; }
    for (i = 1, j = 0; i < n; i++) {               /* bit reversal */
        int bit = n >> 1;
        for (; j & bit; bit >>= 1) j ^= bit;
        j ^= bit;
        if (i < j) { float t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; }
    }
    for (len = 2; len <= n; len <<= 1) {            /* radix-2 butterflies */
        float ang = -2.0f * 3.14159265f / len, wr = cosf(ang), wi = sinf(ang);
        half = len >> 1;
        for (i = 0; i < n; i += len) {
            float cr = 1, ci = 0;
            for (k = 0; k < half; k++) {
                float vr = re[i + k + half] * cr - im[i + k + half] * ci;
                float vi = re[i + k + half] * ci + im[i + k + half] * cr;
                float ur = re[i + k], ui = im[i + k], t;
                re[i + k] = ur + vr; im[i + k] = ui + vi;
                re[i + k + half] = ur - vr; im[i + k + half] = ui - vi;
                t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t;
            }
        }
    }
    for (i = 0; i < 512; i++) out512[i] = sqrtf(re[i] * re[i] + im[i] * im[i]) * (2.0f / n);
    return 1;
}

/* duration / format of a file without playing it. 1 = ok */
NCA_API int nca_probe(const nca_char *path, nca_info *info)
{
    ma_decoder d; ma_decoder_config c;
    nca_setup();
    c = nca_cfg(0);
    if (nca_decoder_init_file(path, &c, &d) != MA_SUCCESS) return 0;
    nca_fill_info(&d, path, info, nca_src_len(&d, NULL));
    ma_decoder_uninit(&d);
    return 1;
}

NCA_API void nca_uninit(void)
{
    g_shuttingDown = 1;
    nca_close();
    if (g_engThread) {
        InterlockedExchange(&g_engQuit, 1); SetEvent(g_engWake);
        if (WaitForSingleObject(g_engThread, 2000) != WAIT_OBJECT_0)
            nca_log("audio engine thread did not finish within 2 s (device operation '%s'), exiting anyway", g_opName);
        else { CloseHandle(g_engThread); g_engThread = NULL; }
    }
#ifdef _WIN32
    if (g_mfStarted && !g_engThread) { pMFShutdown(); g_mfStarted = 0; }
#endif
}

/* ------------------------------------------------------------------ */
/* device robustness: follow the default endpoint, recover stopped /   */
/* invalidated / silent-stuck devices                                 */
/* ------------------------------------------------------------------ */
#ifdef __APPLE__
#include <CoreAudio/CoreAudio.h>
/* UID (ASCII, widened into WCHAR) + liveness of the current default output device; 0 = none */
static int nca_default_endpoint(WCHAR *id, int cap, DWORD *state)
{
    AudioObjectPropertyAddress a = { kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain };
    AudioDeviceID dev = kAudioObjectUnknown; UInt32 sz = sizeof dev; CFStringRef uid = NULL; char u8[256]; int i, ok = 0;
    if (g_testDefOn) {                  /* NCAMP_TEST_DEVICE: simulated endpoint ("" = none) */
        if (!g_testDef[0]) return 0;
        wcsncpy(id, g_testDef, cap - 1); id[cap - 1] = 0;
        if (state) *state = DEVICE_STATE_ACTIVE;
        return 1;
    }
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &a, 0, NULL, &sz, &dev) != noErr || dev == kAudioObjectUnknown) return 0;
    a.mSelector = kAudioDevicePropertyDeviceUID; a.mScope = kAudioObjectPropertyScopeGlobal; sz = sizeof uid;
    if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &uid) == noErr && uid) {
        if (CFStringGetCString(uid, u8, sizeof u8, kCFStringEncodingUTF8)) {
            for (i = 0; u8[i] && i < cap - 1; i++) id[i] = (WCHAR)(unsigned char)u8[i];
            id[i] = 0; ok = 1;
        }
        CFRelease(uid);
    }
    if (ok && state) {
        UInt32 alive = 1; sz = sizeof alive;
        a.mSelector = kAudioDevicePropertyDeviceIsAlive;
        if (AudioObjectGetPropertyData(dev, &a, 0, NULL, &sz, &alive) != noErr) alive = 1;
        *state = alive ? DEVICE_STATE_ACTIVE : 0;
    }
    return ok;
}
#else
static const GUID nca_CLSID_MMDeviceEnumerator = {0xBCDE0395, 0xE52F, 0x467C, {0x8E, 0x3D, 0xC4, 0x57, 0x92, 0x91, 0x69, 0x2E}};
static const GUID nca_IID_IMMDeviceEnumerator  = {0xA95664D2, 0x9614, 0x4F35, {0xA7, 0x46, 0xDE, 0x8D, 0xB6, 0x36, 0x17, 0xE6}};

/* id + state of the current default render (console) endpoint; 0 = unavailable */
static int nca_default_endpoint(WCHAR *id, int cap, DWORD *state)
{
    IMMDeviceEnumerator *e = NULL; IMMDevice *d = NULL; LPWSTR s = NULL; int ok = 0;
    HRESULT ci;
    if (g_testDefOn) {                  /* NCAMP_TEST_DEVICE: simulated endpoint ("" = none) */
        if (!g_testDef[0]) return 0;
        wcsncpy(id, g_testDef, cap - 1); id[cap - 1] = 0;
        if (state) *state = DEVICE_STATE_ACTIVE;
        return 1;
    }
    ci = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
    if (SUCCEEDED(CoCreateInstance(&nca_CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL, &nca_IID_IMMDeviceEnumerator, (void**)&e))) {
        if (SUCCEEDED(IMMDeviceEnumerator_GetDefaultAudioEndpoint(e, eRender, eConsole, &d))) {
            if (SUCCEEDED(IMMDevice_GetId(d, &s))) { wcsncpy(id, s, cap - 1); id[cap - 1] = 0; CoTaskMemFree(s); ok = 1; }
            if (state && FAILED(IMMDevice_GetState(d, state))) *state = 0;
            IMMDevice_Release(d);
        }
        IMMDeviceEnumerator_Release(e);
    }
    if (ci == S_OK || ci == S_FALSE) CoUninitialize();
    return ok;
}
#endif /* __APPLE__ / _WIN32 */

static void nca_remember_endpoint(void)
{
    DWORD st = 0;
    g_openId[0] = 0;
    if (nca_default_endpoint(g_openId, 512, &st)) nca_log("default endpoint id=%ls state=%lu", g_openId, st);
    else nca_log("default endpoint id: unavailable (backend %s)", ma_get_backend_name(g_dev.pContext->backend));
}

/* Auto-pause (1.7.8): called whenever the endpoint we play on may have changed. A *real* change
   is a different endpoint id than before (another default, or none at all) - like headphones
   being unplugged on a phone, playback pauses at the current position. Not a change:
   - same endpoint id: internal recoveries (stuck-stream watchdog, stopped / interrupted device,
     decoder rebuild for a new rate) only bring back the device the listener is already using;
   - no endpoint before ("" - nothing open yet, e.g. no device at start-up while auto-resuming):
     nothing was taken away from the listener.
   Every real change while playing pauses - the first one, the tenth one, however close together
   they come. The only exception is a burst: Windows reports one Bluetooth connect / disconnect as
   several changes (HFP -> A2DP endpoint, default switching twice, ...), so changes within
   NCA_BURST_MS of the last auto-pause belong to that pause and do not pause again (a Play pressed
   meanwhile is not undone). The burst is measured from the pause itself and is not extended by
   later changes: 2.0.0 and earlier used a 10 s window restarted by every change, including the
   ones it skipped, so after the first pause the follow-up notifications of each connect kept the
   window open and later real changes were taken as "part of the same change" and never paused. */
static void nca_endpoint_check(const WCHAR *oldId, const WCHAR *newId, const char *why)
{
    ULONGLONG now = GetTickCount64(); int paused = 0;
    const WCHAR *nw = newId[0] ? newId : L"(none)";
    if (!oldId[0] || wcscmp(oldId, newId) == 0) return;
    if (g_lastAutoPause && now - g_lastAutoPause < NCA_BURST_MS) {
        nca_log("device change %ls -> %ls (%s): %.1f s after the auto-pause, same change, no pause", oldId, nw, why,
                (double)(now - g_lastAutoPause) / 1000.0);
        return;
    }
    EnterCriticalSection(&g_cs);
    if (g_dec && g_state == NCA_PLAYING) { g_state = NCA_PAUSED; paused = 1; }
    LeaveCriticalSection(&g_cs);
    if (paused) {
        g_lastAutoPause = now;
        snprintf(g_autoWhy, sizeof g_autoWhy, "output device changed (%s): %ls -> %ls", why, oldId, nw);
        InterlockedExchange(&g_autoPaused, 1);
        nca_log("auto-pause: %s", g_autoWhy);
    } else nca_log("device change %ls -> %ls (%s): not playing, switched silently", oldId, nw, why);
}

/* the UI asks after every nca_poll: 1 = playback was paused because the device changed */
NCA_API int nca_take_autopause(char *buf, int cap)
{
    if (!InterlockedExchange(&g_autoPaused, 0)) return 0;
    if (buf && cap > 0) { strncpy(buf, g_autoWhy, cap - 1); buf[cap - 1] = 0; }
    return 1;
}

/* tear the device down and open it again on the current default endpoint, keeping the
   track, its position and the play state (except for an auto-pause, see above) */
/* The decoder resamples to the device rate: when the device came back at another rate, build a
   new decoder for it at the same position (engine thread; the decoder lock is held only to read
   the state and to swap). A track opened, closed or seeked by the UI meanwhile wins. */
static void nca_rebuild_decoder(void)
{
    static nca_char path[NCA_MAXPATH];
    ma_decoder *d, *old; ma_decoder_config cfg; unsigned gen; ma_uint32 rate = g_devRate, sr = 0;
    ma_uint64 c = 0, srcLen, outLen, t; double posSec = 0;
    EnterCriticalSection(&g_cs);
    if (!g_dec || !g_path[0] || !rate || g_dec->outputSampleRate == rate) { LeaveCriticalSection(&g_cs); return; }
    gen = g_decGen; nca_strcpy(path, g_path);
    if (ma_decoder_get_cursor_in_pcm_frames(g_dec, &c) == MA_SUCCESS && g_dec->outputSampleRate) posSec = (double)c / g_dec->outputSampleRate;
    LeaveCriticalSection(&g_cs);
    d = (ma_decoder*)malloc(sizeof(ma_decoder)); if (!d) return;
    cfg = nca_cfg(1);
    if (nca_decoder_init_file(path, &cfg, d) != MA_SUCCESS) { free(d); nca_log("decoder rebuild for %u Hz failed", rate); return; }
    srcLen = nca_src_len(d, &sr); outLen = nca_out_len(d, srcLen, sr);
    ma_decoder_seek_to_pcm_frame(d, 0);
    EnterCriticalSection(&g_cs);
    if (gen != g_decGen || !g_dec) { LeaveCriticalSection(&g_cs); ma_decoder_uninit(d); free(d); nca_log("decoder rebuild dropped: the track changed meanwhile"); return; }
    /* the position now (it moved on, or the listener seeked, while the new decoder was built) */
    if (ma_decoder_get_cursor_in_pcm_frames(g_dec, &c) == MA_SUCCESS && g_dec->outputSampleRate) posSec = (double)c / g_dec->outputSampleRate;
    t = (ma_uint64)(posSec * rate);
    if (outLen && t > outLen) t = outLen;
    if (t && ma_decoder_seek_to_pcm_frame(d, t) != MA_SUCCESS) {
        /* could not get back there (see nca_seek): near the end, the track is over */
        ma_decoder_seek_to_pcm_frame(d, 0);
        if (outLen && t + rate >= outLen && g_state == NCA_PLAYING) { g_state = NCA_ENDED; g_endReason = 3; g_endPos = posSec; }
        nca_log("decoder rebuild: seek to %.2f s failed", posSec);
    }
    old = g_dec; g_dec = d; g_lenFrames = outLen;        /* the play state stays as it is now */
    LeaveCriticalSection(&g_cs);
    ma_decoder_uninit(old); free(old);
    nca_log("decoder rebuilt for %u Hz, resumed at %.2f s (length %.2f s)", rate, posSec, outLen ? (double)outLen / rate : 0.0);
}

/* (engine thread) open the device on the current default endpoint; 1 = ok */
static int nca_device_start_up(void)
{
    nca_op("open");
    if (!nca_device_open()) { nca_op(NULL); return 0; }
    nca_op(NULL);
    g_devInited = 1; g_devOk = 1; g_devRate = g_dev.sampleRate;
    return 1;
}

/* (engine thread) tear the device down and open it again on the current default endpoint, keeping
   the track, its position and the play state (except for an auto-pause, see above) */
static void nca_reopen(const char *why)
{
    WCHAR oldId[512]; int closed;
    if (g_ownerThread && GetCurrentThreadId() != g_ownerThread) { nca_log("reopen from a foreign thread refused"); return; }
    wcscpy(oldId, g_openId);
    nca_log("reopening audio device: %s", why);
    g_reopening = 1;
    nca_op("close"); closed = nca_device_close(0); nca_op(NULL);
    if (!closed) { g_reopening = 0; g_needRestart = 1; return; }
    g_devOk = 0; g_devRate = 0;
    if (!nca_device_start_up()) {
        g_reopening = 0; nca_log("reopen failed, will retry in 2 s");
        g_openId[0] = 0;                /* no device now */
        nca_endpoint_check(oldId, L"", why);
        return;
    }
    g_reopening = 0;
    nca_remember_endpoint();
    nca_endpoint_check(oldId, g_openId, why);   /* before a rebuild, which keeps the (paused) state */
    nca_rebuild_decoder();
    nca_describe();
}

/* NCAMP_TEST_DEVICE=<mode>: simulated device events (Wine has no real endpoints). Times are from
   the first nca_poll. Real changes (should auto-pause once): reopen (+5 s a default appears from
   nothing - no pause, +10 s it switches - pause), change (+5 s speakers -> earbuds-hfp, +6.5 s ->
   earbuds-a2dp), remove (+5 s earbuds unplugged, no device for 4 s, then speakers), reroute (+5 s
   miniaudio reroutes to new earbuds), repeat (8 changes over 54 s: earbuds out / in again and again,
   via default switch, miniaudio reroute and unplug, with HFP -> A2DP follow-ups 1.5 s later; press
   Play after each pause - every change except the follow-ups pauses). Not changes (no pause): stop (device stops, same endpoint),
   stuck (callback watchdog), rate (same endpoint comes back at 44.1 kHz: decoder rebuild),
   nodev (no device for the first 6 s at start-up). */
static void nca_test_init(void)
{
    char v[16] = "";
    if (g_testMode >= 0) return;
    GetEnvironmentVariableA("NCAMP_TEST_DEVICE", v, sizeof v);
    g_testMode = !strcmp(v, "stop") ? 1 : !strcmp(v, "reopen") ? 2 : !strcmp(v, "nodev") ? 4 : !strcmp(v, "change") ? 5 :
                 !strcmp(v, "remove") ? 6 : !strcmp(v, "stuck") ? 7 : !strcmp(v, "rate") ? 8 : !strcmp(v, "reroute") ? 9 : !strcmp(v, "repeat") ? 10 : !strcmp(v, "stress") ? 11 : !strcmp(v, "hang") ? 12 : 0;
    if (g_testMode == 4) g_testNoDevUntil = GetTickCount64() + 6000;
    if (g_testMode == 11) {
        char r[4] = "";
        GetEnvironmentVariableA("NCAMP_TEST_ROUTING", r, sizeof r);
        if (r[0] == '1') { g_testRouteEv = CreateEventA(NULL, FALSE, FALSE, NULL); CloseHandle(CreateThread(NULL, 0, nca_test_router, NULL, 0, NULL)); }
    }
    if (g_testMode == 1 || g_testMode >= 5) { g_testDefOn = 1; wcscpy(g_testDef, g_testMode == 6 ? L"{TEST}.{earbuds}" : L"{TEST}.{speakers}"); }
}

static void nca_test_set(const WCHAR *id)
{
    g_testDefOn = 1; wcscpy(g_testDef, id);
    if (g_testRouteEv) SetEvent(g_testRouteEv);
}

/* the device's write fails once (like WASAPI after the endpoint is gone): miniaudio's worker
   stops the device by itself and posts "stopped" - the path real device loss takes */
static ma_result (*g_testOrigWrite)(ma_device*, const void*, ma_uint32, ma_uint32*) = NULL;
static ma_result nca_test_write(ma_device *d, const void *p, ma_uint32 n, ma_uint32 *w)
{
    if (g_testFailWrite) { g_testFailWrite = 0; return MA_ERROR; }
    return g_testOrigWrite(d, p, n, w);
}
static void nca_test_device_opened(void)
{
    if (g_testMode <= 0 || !g_dev.pContext->callbacks.onDeviceWrite) return;
    if (g_dev.pContext->callbacks.onDeviceWrite != nca_test_write) {
        g_testOrigWrite = g_dev.pContext->callbacks.onDeviceWrite;
        g_dev.pContext->callbacks.onDeviceWrite = nca_test_write;
    }
}

/* NCAMP_TEST_ROUTING=1 (with stress): does to g_dev what miniaudio's WASAPI notification thread
   does on a default-device change when automatic stream routing is on - stop, restart, post
   "rerouted" - from its own thread. Only acts while routing is on, which 2.0.0 had and 2.0.1
   does not: it reproduces the 2.0.0 race. */
static DWORD WINAPI nca_test_router(LPVOID unused)
{
    (void)unused;
    for (;;) {
        WaitForSingleObject(g_testRouteEv, INFINITE);
        if (g_shuttingDown) break;
        if (!g_autoRouting || !g_devInited) continue;
        if (ma_device_get_state(&g_dev) == ma_device_state_started) {
            ma_device_stop(&g_dev);
            Sleep(1);
            ma_device_start(&g_dev);
        }
        g_needDescribe = 1;
    }
    return 0;
}

static void nca_test_step(ULONGLONG t, int *step)
{
    int m = g_testMode;
    if (m <= 0 || m == 4) return;
    if (m == 11) {  /* stress: random device events every 60-700 ms, Play pressed again after each auto-pause */
        static ULONGLONG next = 0, lastStat = 0; static unsigned seed = 12345, n = 0, k[7];
        static const WCHAR *ids[] = { L"{TEST}.{speakers}", L"{TEST}.{earbuds-hfp}", L"{TEST}.{earbuds-a2dp}" };
        unsigned r;
        if (t < 3000) return;
        if (t >= next) {
            seed = seed * 1103515245u + 12345u; r = (seed >> 8) % 1000;
            next = t + 60 + (r * 7 % 640);
            switch (r % 7) {
            case 0: case 1: nca_test_set(ids[(r / 7) % 3]); break;                    /* default switches (bursts when close) */
            case 2: nca_test_set(L""); g_testNoDevUntil = GetTickCount64() + 200 + r % 1300; g_testFailWrite = 1; break; /* endpoint gone */
            case 3: g_testFailWrite = 1; break;                                       /* device fails, same endpoint */
            case 4: g_needDescribe = 1; break;                                        /* "rerouted" */
            case 5: g_testRate = g_testRate ? 0 : 44100; g_needRestart = 1; break;   /* comes back at another rate */
            case 6: g_testStuck = 1; break;                                           /* callbacks stall */
            }
            k[r % 7]++; n++;
            if (g_testDefOn && !g_testDef[0] && GetTickCount64() >= g_testNoDevUntil) nca_test_set(ids[0]);
            if (g_state == NCA_PAUSED) nca_play();                                    /* the listener presses Play */
        }
        if (t - lastStat >= 10000) {
            lastStat = t;
            nca_log("TEST stress: %u events (switch %u, gone %u, fail %u, reroute %u, rate %u, stuck %u), device state %d",
                    n, k[0] + k[1], k[2], k[3], k[4], k[5], k[6], g_devInited ? (int)ma_device_get_state(&g_dev) : -1);
        }
        return;
    }
    if (m == 10) {  /* repeat: real changes again and again, Play pressed after each pause (by the tester) */
        static const struct { unsigned ms; int kind; const WCHAR *id; const char *what; } ev[] = {
            {  5000, 0, L"{TEST}.{earbuds-hfp}",  "earbuds out of the case (HFP): speakers -> earbuds" },
            {  6500, 0, L"{TEST}.{earbuds-a2dp}", "earbuds switch HFP -> A2DP (1.5 s later, same change)" },
            { 22000, 1, L"{TEST}.{speakers}",     "earbuds back in the case: miniaudio reroutes to the speakers" },
            { 38000, 0, L"{TEST}.{earbuds-hfp}",  "earbuds out again (HFP): speakers -> earbuds" },
            { 39500, 0, L"{TEST}.{earbuds-a2dp}", "earbuds switch HFP -> A2DP (1.5 s later, same change)" },
            { 46000, 2, L"",                      "earbuds back in the case: endpoint gone, no device for 1.5 s" },
            { 47500, 0, L"{TEST}.{speakers}",     "speakers become the default" },
            { 54000, 0, L"{TEST}.{earbuds-a2dp}", "earbuds out again: speakers -> earbuds" },
        };
        while (*step < (int)(sizeof ev / sizeof ev[0]) && t >= ev[*step].ms) {
            int k = (*step)++;
            nca_log("TEST: %s", ev[k].what);
            nca_test_set(ev[k].id);
            if (ev[k].kind == 1) g_needDescribe = 1;
            if (ev[k].kind == 2) { g_testNoDevUntil = GetTickCount64() + 1500; g_testFailWrite = 1; }
        }
        return;
    }
    if (*step == 0 && t >= 5000) {
        (*step)++;
        if (m == 1) { nca_log("TEST: simulating device stop"); g_testFailWrite = 1; }
        if (m == 2) { nca_log("TEST: earbuds connected, become the default endpoint"); nca_test_set(L"{TEST}.{earbuds-1}"); }
        if (m == 5) { nca_log("TEST: earbuds connected (HFP), default speakers -> earbuds"); nca_test_set(L"{TEST}.{earbuds-hfp}"); }
        if (m == 6) { nca_log("TEST: earbuds unplugged, no device for 4 s"); nca_test_set(L""); g_testNoDevUntil = GetTickCount64() + 4000; g_testFailWrite = 1; }
        if (m == 7) { nca_log("TEST: callbacks stall"); g_testStuck = 1; }
        if (m == 8) { nca_log("TEST: same device comes back at 44100 Hz"); g_testRate = 44100; g_needRestart = 1; }
        if (m == 12) { nca_log("TEST: device fails and its driver hangs in stop for 6 s"); g_testHangMs = 6000; g_testFailWrite = 1; }
        if (m == 9) { nca_log("TEST: miniaudio reroutes to new earbuds"); nca_test_set(L"{TEST}.{earbuds}"); g_needDescribe = 1; }
    }
    if (*step == 1 && t >= (m == 5 ? 6500u : 9000u) && (m == 5 || m == 6)) {
        (*step)++;
        if (m == 5) { nca_log("TEST: earbuds switch HFP -> A2DP endpoint"); nca_test_set(L"{TEST}.{earbuds-a2dp}"); }
        if (m == 6) { nca_log("TEST: speakers become the default"); nca_test_set(L"{TEST}.{speakers}"); }
    }
    if (*step == 1 && t >= 10000 && m == 2) { (*step)++; nca_log("TEST: default endpoint switched again"); nca_test_set(L"{TEST}.{earbuds-2}"); }
}

/* (engine thread) every 25 ms: follow the default endpoint, recover failed / stuck devices */
static void nca_engine_tick(void)
{
    static ULONGLONG lastCheck = 0, lastEp = 0, t0 = 0; static LONG lastCb = 0; static int step = 0; static DWORD lastSt = DEVICE_STATE_ACTIVE;
    ULONGLONG now = GetTickCount64();
    if (!t0) t0 = lastCheck = lastEp = now;   /* first stall check 2 s after the thread starts, not at once */
    if (g_shuttingDown) return;
    if (!g_devOk) {              /* a reopen failed earlier: retry every 2 s */
        if (now - lastCheck >= 2000) { lastCheck = now; nca_reopen("retry"); }
        return;
    }
    nca_test_step(now - t0, &step);
    if (g_needDescribe) {        /* "rerouted" notification (miniaudio's stream routing is off since 2.0.1; kept to be safe) */
        WCHAR oldId[512];
        g_needDescribe = 0; wcscpy(oldId, g_openId);
        nca_log("rerouted by miniaudio"); nca_remember_endpoint();
        nca_endpoint_check(oldId, g_openId, "rerouted to the new default");
        nca_describe();
    }
    if (g_needRestart) { g_needRestart = 0; nca_reopen("device stopped / interrupted"); lastCheck = lastEp = now; return; }
    nca_rebuild_decoder();       /* a track opened by the UI while the device ran at another rate */
    if (now - lastEp >= 500) {  /* follow the default endpoint (miniaudio's own stream routing is off) */
        WCHAR id[512]; DWORD st = 0;
        lastEp = now;
        if (!g_openId[0] && nca_default_endpoint(id, 512, &st) && st == DEVICE_STATE_ACTIVE) {
            /* opened without a real endpoint (e.g. null backend) and one has appeared */
            nca_log("default endpoint appeared: %ls", id); nca_reopen("default endpoint appeared"); return;
        }
        if (g_openId[0] && nca_default_endpoint(id, 512, &st)) {
            if (wcscmp(id, g_openId) != 0) { nca_log("default endpoint changed: %ls -> %ls", g_openId, id); nca_reopen("default endpoint changed"); return; }
            if (st != DEVICE_STATE_ACTIVE && st != lastSt) nca_log("default endpoint state=%lu", st);
            lastSt = st;
        }
    }
    if (now - lastCheck < 2000) return;
    lastCheck = now;
    if (ma_device_get_state(&g_dev) != ma_device_state_started) { nca_reopen("device not running"); return; }
    {   /* callbacks stalled although the device claims to run (stuck stream) */
        LONG cbs = g_cbTotal;
        if (cbs == lastCb || g_testStuck) { g_testStuck = 0; nca_reopen("no audio callbacks for 2 s"); lastCb = g_cbTotal; return; }
        lastCb = cbs;
    }
}

static DWORD WINAPI nca_engine_thread(LPVOID unused)
{
#ifdef _WIN32
    HRESULT ci = CoInitializeEx(NULL, COINIT_MULTITHREADED);
#endif
    (void)unused;
    g_ownerThread = GetCurrentThreadId();
    if (nca_device_start_up()) { nca_remember_endpoint(); nca_describe(); }
    SetEvent(g_engReady);
    while (!g_engQuit) {
        WaitForSingleObject(g_engWake, 25);
        if (g_engQuit) break;
        nca_engine_tick();
    }
    nca_op("close at exit"); nca_device_close(1); nca_op(NULL);
    g_devOk = 0; g_devRate = 0;
#ifdef _WIN32
    if (ci == S_OK || ci == S_FALSE) CoUninitialize();
#endif
    return 0;
}

/* Called from the UI thread several times a second. Never waits for the device: it only logs
   what the engine noticed and watches the engine thread. */
NCA_API void nca_poll(void)
{
    static ULONGLONG warned = 0; static LONG lastBusy = 0;
    ULONGLONG since = g_opSince, now = GetTickCount64();
    if (g_endReason) {
        int r = g_endReason; g_endReason = 0;
        nca_log("end of stream at %.2f s (%s)", g_endPos, r == 3 ? "seek to the end" : r == 2 ? "known length reached" : "decoder EOF");
    }
    if (since && now - since >= 3000 && since != warned) {
        warned = since;
        nca_log("watchdog: audio device operation '%s' has not finished after %.1f s (the player stays usable)", g_opName, (double)(now - since) / 1000.0);
    }
    if (g_cbBusy != lastBusy && now % 1000 < 30) {
        nca_log("audio callback found the decoder busy %ld times (played silence)", g_cbBusy - lastBusy);
        lastBusy = g_cbBusy;
    }
}
