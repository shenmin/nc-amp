/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * ncaudio - the nc-amp audio engine (ncaudio.dll), built only from open-source parts:
 *   miniaudio (playback device; MP3/FLAC/WAV decoding via its bundled dr_libs code),
 *   stb_vorbis (Ogg Vorbis), libopus + opusfile + libogg (Opus),
 *   Windows Media Foundation (M4A / AAC, decoded by the OS - no codec is bundled).
 * Plain C API used from Free Pascal (ncaudio.pas). All paths are UTF-16 (wchar_t).
 */
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <math.h>
#include <string.h>
#include <stdio.h>
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

#define NCA_API __declspec(dllexport)

/* ------------------------------------------------------------------ */
/* Media Foundation decoding backend (m4a / mp4 / aac)                 */
/* ------------------------------------------------------------------ */
typedef struct {
    ma_data_source_base ds;
    IMFSourceReader *reader;
    ma_uint32 channels, rate;
    ma_uint64 length;          /* frames, 0 = unknown */
    ma_uint64 cursor;          /* frames delivered so far */
    float *buf; ma_uint32 bufFrames, bufPos, bufCap;
    int eof;
} nca_mf;

static int g_mfStarted = 0;

/* Media Foundation is loaded on demand so the engine still works (minus AAC) on
   Windows "N" editions without the Media Feature Pack */
typedef HRESULT (WINAPI *pfnMFStartup)(ULONG, DWORD);
typedef HRESULT (WINAPI *pfnMFShutdown)(void);
typedef HRESULT (WINAPI *pfnMFCreateMediaType)(IMFMediaType**);
typedef HRESULT (WINAPI *pfnMFCreateSourceReaderFromURL)(LPCWSTR, IMFAttributes*, IMFSourceReader**);
static pfnMFStartup pMFStartup; static pfnMFShutdown pMFShutdown;
static pfnMFCreateMediaType pMFCreateMediaType; static pfnMFCreateSourceReaderFromURL pMFCreateSourceReaderFromURL;
static int nca_mf_load(void)
{
    static int tried = 0, ok = 0; HMODULE a, b;
    if (tried) return ok;
    tried = 1;
    a = LoadLibraryW(L"mfplat.dll"); b = LoadLibraryW(L"mfreadwrite.dll");
    if (!a || !b) return 0;
    pMFStartup = (pfnMFStartup)GetProcAddress(a, "MFStartup");
    pMFShutdown = (pfnMFShutdown)GetProcAddress(a, "MFShutdown");
    pMFCreateMediaType = (pfnMFCreateMediaType)GetProcAddress(a, "MFCreateMediaType");
    pMFCreateSourceReaderFromURL = (pfnMFCreateSourceReaderFromURL)GetProcAddress(b, "MFCreateSourceReaderFromURL");
    ok = pMFStartup && pMFShutdown && pMFCreateMediaType && pMFCreateSourceReaderFromURL;
    return ok;
}

static int nca_mf_fill(nca_mf *m)
{
    DWORD idx, flags = 0; LONGLONG ts = 0; IMFSample *s = NULL; IMFMediaBuffer *mb = NULL;
    BYTE *p; DWORD len = 0; HRESULT hr;
    for (;;) {
        s = NULL;
        hr = IMFSourceReader_ReadSample(m->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, &idx, &flags, &ts, &s);
        if (FAILED(hr)) { m->eof = 1; return 0; }
        if (flags & MF_SOURCE_READERF_ENDOFSTREAM) { if (s) IMFSample_Release(s); m->eof = 1; return 0; }
        if (s) break;
    }
    hr = IMFSample_ConvertToContiguousBuffer(s, &mb);
    m->bufFrames = m->bufPos = 0;
    if (SUCCEEDED(hr) && SUCCEEDED(IMFMediaBuffer_Lock(mb, &p, NULL, &len))) {
        ma_uint32 frames = len / (sizeof(float) * m->channels);
        if (frames > m->bufCap) {
            float *nb = (float*)realloc(m->buf, (size_t)frames * m->channels * sizeof(float));
            if (nb) { m->buf = nb; m->bufCap = frames; } else frames = 0;
        }
        if (frames) memcpy(m->buf, p, (size_t)frames * m->channels * sizeof(float));
        m->bufFrames = frames;
        IMFMediaBuffer_Unlock(mb);
    }
    if (mb) IMFMediaBuffer_Release(mb);
    IMFSample_Release(s);
    return 1;
}

static ma_result nca_mf_read(ma_data_source *pDS, void *out, ma_uint64 frameCount, ma_uint64 *pRead)
{
    nca_mf *m = (nca_mf*)pDS; ma_uint64 done = 0; float *o = (float*)out;
    while (done < frameCount) {
        ma_uint64 n;
        if (m->bufPos >= m->bufFrames) { if (m->eof || !nca_mf_fill(m)) break; continue; }
        n = m->bufFrames - m->bufPos; if (n > frameCount - done) n = frameCount - done;
        if (o) memcpy(o + done * m->channels, m->buf + (size_t)m->bufPos * m->channels, (size_t)n * m->channels * sizeof(float));
        m->bufPos += (ma_uint32)n; done += n;
    }
    m->cursor += done;
    if (pRead) *pRead = done;
    return (done == 0 && frameCount > 0) ? MA_AT_END : MA_SUCCESS;
}

static ma_result nca_mf_seek(ma_data_source *pDS, ma_uint64 frame)
{
    nca_mf *m = (nca_mf*)pDS; PROPVARIANT pv;
    PropVariantInit(&pv); pv.vt = VT_I8; pv.hVal.QuadPart = (LONGLONG)(frame * 10000000ULL / m->rate);
    if (FAILED(IMFSourceReader_SetCurrentPosition(m->reader, &GUID_NULL, &pv))) return MA_ERROR;
    m->bufFrames = m->bufPos = 0; m->eof = 0; m->cursor = frame;
    return MA_SUCCESS;
}

static ma_result nca_mf_format(ma_data_source *pDS, ma_format *f, ma_uint32 *ch, ma_uint32 *sr, ma_channel *map, size_t cap)
{
    nca_mf *m = (nca_mf*)pDS;
    if (f) *f = ma_format_f32;
    if (ch) *ch = m->channels;
    if (sr) *sr = m->rate;
    if (map) ma_channel_map_init_standard(ma_standard_channel_map_default, map, cap, m->channels);
    return MA_SUCCESS;
}
static ma_result nca_mf_cursor(ma_data_source *pDS, ma_uint64 *c) { *c = ((nca_mf*)pDS)->cursor; return MA_SUCCESS; }
static ma_result nca_mf_length(ma_data_source *pDS, ma_uint64 *l) { *l = ((nca_mf*)pDS)->length; return MA_SUCCESS; }

static ma_data_source_vtable g_nca_mf_ds_vtable = { nca_mf_read, nca_mf_seek, nca_mf_format, nca_mf_cursor, nca_mf_length, NULL, 0 };

static int nca_ext_is(const wchar_t *path, const wchar_t *const *exts)
{
    const wchar_t *dot = wcsrchr(path, L'.');
    if (!dot) return 0;
    for (; *exts; exts++) if (_wcsicmp(dot, *exts) == 0) return 1;
    return 0;
}

static const wchar_t *const g_mfExts[] = { L".m4a", L".mp4", L".aac", L".m4b", L".3gp", NULL };

static ma_result nca_mf_init_file_w(void *ud, const wchar_t *path, const ma_decoding_backend_config *cfg,
                                    const ma_allocation_callbacks *alloc, ma_data_source **ppDS)
{
    nca_mf *m; IMFMediaType *mt = NULL, *cur = NULL; PROPVARIANT pv; HRESULT hr;
    UINT32 ch = 0, sr = 0;
    (void)ud; (void)cfg; (void)alloc;
    if (!nca_ext_is(path, g_mfExts)) return MA_INVALID_FILE;
    if (!nca_mf_load()) return MA_INVALID_FILE;
    CoInitializeEx(NULL, COINIT_MULTITHREADED);   /* no-op if this thread already has COM */
    if (!g_mfStarted) { if (FAILED(pMFStartup(MF_VERSION, MFSTARTUP_LITE))) return MA_ERROR; g_mfStarted = 1; }
    m = (nca_mf*)calloc(1, sizeof(*m));
    if (!m) return MA_OUT_OF_MEMORY;
    hr = pMFCreateSourceReaderFromURL(path, NULL, &m->reader);
    if (FAILED(hr)) { free(m); return MA_INVALID_FILE; }
    IMFSourceReader_SetStreamSelection(m->reader, (DWORD)MF_SOURCE_READER_ALL_STREAMS, FALSE);
    IMFSourceReader_SetStreamSelection(m->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, TRUE);
    if (FAILED(pMFCreateMediaType(&mt))) { IMFSourceReader_Release(m->reader); free(m); return MA_ERROR; }
    IMFMediaType_SetGUID(mt, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
    IMFMediaType_SetGUID(mt, &MF_MT_SUBTYPE, &MFAudioFormat_Float);
    hr = IMFSourceReader_SetCurrentMediaType(m->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL, mt);
    IMFMediaType_Release(mt);
    if (FAILED(hr) || FAILED(IMFSourceReader_GetCurrentMediaType(m->reader, (DWORD)MF_SOURCE_READER_FIRST_AUDIO_STREAM, &cur))) {
        IMFSourceReader_Release(m->reader); free(m); return MA_INVALID_FILE;
    }
    IMFMediaType_GetUINT32(cur, &MF_MT_AUDIO_NUM_CHANNELS, &ch);
    IMFMediaType_GetUINT32(cur, &MF_MT_AUDIO_SAMPLES_PER_SECOND, &sr);
    IMFMediaType_Release(cur);
    if (ch == 0 || sr == 0) { IMFSourceReader_Release(m->reader); free(m); return MA_INVALID_FILE; }
    m->channels = ch; m->rate = sr;
    PropVariantInit(&pv);
    if (SUCCEEDED(IMFSourceReader_GetPresentationAttribute(m->reader, (DWORD)MF_SOURCE_READER_MEDIASOURCE, &MF_PD_DURATION, &pv))) {
        m->length = (ma_uint64)(pv.uhVal.QuadPart * (ULONGLONG)sr / 10000000ULL);
        PropVariantClear(&pv);
    }
    {
        ma_data_source_config dc = ma_data_source_config_init();
        dc.vtable = &g_nca_mf_ds_vtable;
        if (ma_data_source_init(&dc, &m->ds) != MA_SUCCESS) { IMFSourceReader_Release(m->reader); free(m); return MA_ERROR; }
    }
    *ppDS = (ma_data_source*)m;
    return MA_SUCCESS;
}

static void nca_mf_uninit(void *ud, ma_data_source *pDS, const ma_allocation_callbacks *alloc)
{
    nca_mf *m = (nca_mf*)pDS; (void)ud; (void)alloc;
    ma_data_source_uninit(&m->ds);
    if (m->reader) IMFSourceReader_Release(m->reader);
    free(m->buf); free(m);
}

static ma_decoding_backend_vtable g_nca_mf_backend = { NULL, NULL, nca_mf_init_file_w, NULL, nca_mf_uninit };

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

static const wchar_t *const g_vbExts[] = { L".ogg", L".oga", NULL };

static int nca_ext_is(const wchar_t *path, const wchar_t *const *exts);

static ma_result nca_vb_init_file_w(void *ud, const wchar_t *path, const ma_decoding_backend_config *cfg,
                                    const ma_allocation_callbacks *alloc, ma_data_source **ppDS)
{
    nca_vorbis *m; FILE *f; int err = 0; stb_vorbis_info vi;
    (void)ud; (void)cfg; (void)alloc;
    if (!nca_ext_is(path, g_vbExts)) return MA_INVALID_FILE;
    f = _wfopen(path, L"rb");
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
static ma_decoding_backend_vtable g_nca_vb_backend = { NULL, NULL, nca_vb_init_file_w, NULL, nca_vb_uninit };

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
static ma_mutex g_lock;
static ma_decoder *g_dec = NULL;
static volatile int g_state = NCA_STOPPED;
static volatile float g_vol = 1.0f, g_pan = 0.0f;
static float g_ring[RING]; static volatile LONG g_ringPos = 0;
static char g_err[256] = "";
static ma_decoding_backend_vtable *g_backends[3];

static void cb(ma_device *dev, void *out, const void *in, ma_uint32 frames)
{
    float *o = (float*)out; ma_uint64 got = 0; ma_uint32 i; float gl, gr, v;
    (void)in; (void)dev;
    ma_mutex_lock(&g_lock);
    if (g_dec && g_state == NCA_PLAYING) {
        ma_decoder_read_pcm_frames(g_dec, o, frames, &got);
        if (got < frames) g_state = NCA_ENDED;
    }
    ma_mutex_unlock(&g_lock);
    if (got < frames) memset(o + got * 2, 0, (size_t)(frames - got) * 2 * sizeof(float));
    {   /* spectrum tap (pre-volume, mono) */
        LONG p = g_ringPos;
        for (i = 0; i < (ma_uint32)got; i++) { g_ring[p] = 0.5f * (o[i*2] + o[i*2+1]); p = (p + 1) & (RING - 1); }
        InterlockedExchange(&g_ringPos, p);
    }
    v = g_vol;
    gl = v * (g_pan > 0 ? 1.0f - g_pan : 1.0f);
    gr = v * (g_pan < 0 ? 1.0f + g_pan : 1.0f);
    for (i = 0; i < (ma_uint32)got; i++) { o[i*2] *= gl; o[i*2+1] *= gr; }
}

NCA_API const char *nca_version(void) { return "miniaudio " MA_VERSION_STRING ", stb_vorbis 1.22, opusfile 0.12 / libopus 1.5.2, Media Foundation (AAC)"; }
NCA_API const char *nca_error(void) { return g_err; }

static void nca_setup(void)
{
    if (!g_lockOk) { ma_mutex_init(&g_lock); g_lockOk = 1; }
    g_backends[0] = &g_nca_vb_backend;
    g_backends[1] = ma_decoding_backend_libopus;
    g_backends[2] = &g_nca_mf_backend;
}

NCA_API int nca_init(void)
{
    ma_device_config dc;
    nca_setup();
    if (g_devOk) return 1;
    dc = ma_device_config_init(ma_device_type_playback);
    dc.playback.format = ma_format_f32;
    dc.playback.channels = 2;
    dc.sampleRate = 0;                  /* device native rate */
    dc.dataCallback = cb;
    dc.performanceProfile = ma_performance_profile_conservative;
    if (ma_device_init(NULL, &dc, &g_dev) != MA_SUCCESS) { strcpy(g_err, "no audio output device"); return 0; }
    if (ma_device_start(&g_dev) != MA_SUCCESS) { ma_device_uninit(&g_dev); strcpy(g_err, "cannot start audio device"); return 0; }
    g_devOk = 1;
    return 1;
}

NCA_API int nca_device_rate(void) { return g_devOk ? (int)g_dev.sampleRate : 0; }

static ma_decoder_config nca_cfg(int forPlayback)
{
    ma_decoder_config c = ma_decoder_config_init(forPlayback ? ma_format_f32 : ma_format_unknown,
                                                 forPlayback ? 2 : 0, forPlayback && g_devOk ? g_dev.sampleRate : 0);
    c.ppCustomBackendVTables = g_backends;
    c.customBackendCount = 3;
    c.seekPointCount = forPlayback ? 4096 : 0;      /* fast, accurate MP3 seeking */
    c.resampling.algorithm = ma_resample_algorithm_linear;
    c.resampling.linear.lpfOrder = 8;
    return c;
}

static void nca_fill_info(ma_decoder *d, const wchar_t *path, nca_info *info)
{
    ma_format f; ma_uint32 ch = 0, sr = 0; ma_uint64 len = 0;
    WIN32_FILE_ATTRIBUTE_DATA fa; const wchar_t *dot;
    memset(info, 0, sizeof(*info));
    if (d->pBackend) ma_data_source_get_data_format(d->pBackend, &f, &ch, &sr, NULL, 0);
    info->channels = (int)ch; info->sample_rate = (int)sr;
    if (d->pBackend && ma_data_source_get_length_in_pcm_frames(d->pBackend, &len) == MA_SUCCESS && sr && len) info->length = (double)len / sr;
    else info->length = -1;
    if (info->length > 0 && GetFileAttributesExW(path, GetFileExInfoStandard, &fa)) {
        double bytes = (double)fa.nFileSizeHigh * 4294967296.0 + fa.nFileSizeLow;
        info->bitrate = (int)(bytes * 8.0 / info->length / 1000.0 + 0.5);
    }
    dot = wcsrchr(path, L'.');
    if (dot) { int i; for (i = 0; i < 15 && dot[i + 1]; i++) info->codec[i] = (char)towupper(dot[i + 1]); }
}

/* open a file for playback; replaces the current one. 1 = ok */
NCA_API int nca_open(const wchar_t *path, nca_info *info)
{
    ma_decoder *d, *old; ma_decoder_config c; ma_result r;
    nca_setup();
    d = (ma_decoder*)malloc(sizeof(ma_decoder));
    if (!d) return 0;
    c = nca_cfg(1);
    r = ma_decoder_init_file_w(path, &c, d);
    if (r != MA_SUCCESS) { free(d); snprintf(g_err, sizeof g_err, "cannot decode (%s)", ma_result_description(r)); return 0; }
    if (info) nca_fill_info(d, path, info);
    ma_mutex_lock(&g_lock);
    old = g_dec; g_dec = d; g_state = NCA_STOPPED;
    ma_mutex_unlock(&g_lock);
    if (old) { ma_decoder_uninit(old); free(old); }
    return 1;
}

NCA_API void nca_close(void)
{
    ma_decoder *old;
    if (!g_lockOk) return;
    ma_mutex_lock(&g_lock); old = g_dec; g_dec = NULL; g_state = NCA_STOPPED; ma_mutex_unlock(&g_lock);
    if (old) { ma_decoder_uninit(old); free(old); }
}

NCA_API void nca_play(void)  { if (!g_lockOk) return; ma_mutex_lock(&g_lock); if (g_dec) g_state = NCA_PLAYING; ma_mutex_unlock(&g_lock); }
NCA_API void nca_pause(void) { if (!g_lockOk) return; ma_mutex_lock(&g_lock); if (g_state == NCA_PLAYING) g_state = NCA_PAUSED; ma_mutex_unlock(&g_lock); }
NCA_API void nca_stop(void)
{
    if (!g_lockOk) return;
    ma_mutex_lock(&g_lock);
    if (g_dec) { g_state = NCA_STOPPED; ma_decoder_seek_to_pcm_frame(g_dec, 0); }
    ma_mutex_unlock(&g_lock);
}
NCA_API int nca_state(void) { return g_state; }

NCA_API double nca_get_pos(void)
{
    ma_uint64 c = 0; double r = 0;
    if (!g_lockOk) return 0;
    ma_mutex_lock(&g_lock);
    if (g_dec && ma_decoder_get_cursor_in_pcm_frames(g_dec, &c) == MA_SUCCESS && g_dec->outputSampleRate)
        r = (double)c / g_dec->outputSampleRate;
    ma_mutex_unlock(&g_lock);
    return r;
}

NCA_API double nca_get_len(void)
{
    ma_uint64 l = 0; double r = 0;
    if (!g_lockOk) return 0;
    ma_mutex_lock(&g_lock);
    if (g_dec && ma_decoder_get_length_in_pcm_frames(g_dec, &l) == MA_SUCCESS && g_dec->outputSampleRate)
        r = (double)l / g_dec->outputSampleRate;
    ma_mutex_unlock(&g_lock);
    return r;
}

NCA_API int nca_seek(double sec)
{
    int ok = 0;
    if (!g_lockOk) return 0;
    if (sec < 0) sec = 0;
    ma_mutex_lock(&g_lock);
    if (g_dec) {
        ok = ma_decoder_seek_to_pcm_frame(g_dec, (ma_uint64)(sec * g_dec->outputSampleRate)) == MA_SUCCESS;
        if (g_state == NCA_ENDED) g_state = NCA_PLAYING;
    }
    ma_mutex_unlock(&g_lock);
    return ok;
}

NCA_API void nca_set_volume(float v) { g_vol = v < 0 ? 0 : (v > 1 ? 1 : v); }
NCA_API void nca_set_pan(float p)    { g_pan = p < -1 ? -1 : (p > 1 ? 1 : p); }

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
NCA_API int nca_probe(const wchar_t *path, nca_info *info)
{
    ma_decoder d; ma_decoder_config c;
    nca_setup();
    c = nca_cfg(0);
    if (ma_decoder_init_file_w(path, &c, &d) != MA_SUCCESS) return 0;
    nca_fill_info(&d, path, info);
    ma_decoder_uninit(&d);
    return 1;
}

NCA_API void nca_uninit(void)
{
    nca_close();
    if (g_devOk) { ma_device_uninit(&g_dev); g_devOk = 0; }
    if (g_mfStarted) { pMFShutdown(); g_mfStarted = 0; }
}
