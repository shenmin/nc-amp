/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * Windows Media Foundation decoding backend (m4a / mp4 / aac)
 * (included by ncaudio.c)
 */
#pragma once
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
