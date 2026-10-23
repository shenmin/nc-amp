/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * macOS AudioToolbox decoding backend (m4a / mp4 / aac / alac / aiff / caf)
 * (included by ncaudio.c)
 */
#pragma once
/* ------------------------------------------------------------------ */
/* AudioToolbox decoding backend (m4a / mp4 / aac / alac / aiff / caf): ExtAudioFile, decoded by macOS */
/* ------------------------------------------------------------------ */
#include <AudioToolbox/AudioToolbox.h>
typedef struct {
    ma_data_source_base ds;
    ExtAudioFileRef file;
    ma_uint32 channels, rate;
    ma_uint64 length, cursor;
} nca_at;

static const char *const g_atExts[] = { ".m4a", ".mp4", ".aac", ".m4b", ".3gp", ".alac", ".aif", ".aiff", ".aifc", ".caf", NULL };

static ma_result nca_at_read(ma_data_source *pDS, void *out, ma_uint64 frameCount, ma_uint64 *pRead)
{
    nca_at *m = (nca_at*)pDS; ma_uint64 done = 0; float tmp[4096];
    while (done < frameCount) {
        UInt32 want = (UInt32)((frameCount - done) > 4096 ? 4096 : (frameCount - done)), n;
        AudioBufferList bl; OSStatus st;
        float *dst = out ? (float*)out + done * m->channels : tmp;
        if (!out && want * m->channels > 4096) want = 4096 / m->channels;
        if (out && want > 4096) want = 4096;
        n = want;
        bl.mNumberBuffers = 1; bl.mBuffers[0].mNumberChannels = m->channels;
        bl.mBuffers[0].mDataByteSize = want * m->channels * (UInt32)sizeof(float); bl.mBuffers[0].mData = dst;
        st = ExtAudioFileRead(m->file, &n, &bl);
        if (st != noErr || n == 0) break;
        done += n;
    }
    m->cursor += done;
    if (pRead) *pRead = done;
    return (done == 0 && frameCount > 0) ? MA_AT_END : MA_SUCCESS;
}
static ma_result nca_at_seek(ma_data_source *pDS, ma_uint64 frame)
{
    nca_at *m = (nca_at*)pDS;
    if (ExtAudioFileSeek(m->file, (SInt64)frame) != noErr) return MA_ERROR;
    m->cursor = frame;
    return MA_SUCCESS;
}
static ma_result nca_at_format(ma_data_source *pDS, ma_format *f, ma_uint32 *ch, ma_uint32 *sr, ma_channel *map, size_t cap)
{
    nca_at *m = (nca_at*)pDS;
    if (f) *f = ma_format_f32;
    if (ch) *ch = m->channels;
    if (sr) *sr = m->rate;
    if (map) ma_channel_map_init_standard(ma_standard_channel_map_default, map, cap, m->channels);
    return MA_SUCCESS;
}
static ma_result nca_at_cursor(ma_data_source *pDS, ma_uint64 *c) { *c = ((nca_at*)pDS)->cursor; return MA_SUCCESS; }
static ma_result nca_at_length(ma_data_source *pDS, ma_uint64 *l) { *l = ((nca_at*)pDS)->length; return MA_SUCCESS; }
static ma_data_source_vtable g_nca_at_ds_vtable = { nca_at_read, nca_at_seek, nca_at_format, nca_at_cursor, nca_at_length, NULL, 0 };

static ma_result nca_at_init_file(void *ud, const char *path, const ma_decoding_backend_config *cfg,
                                  const ma_allocation_callbacks *alloc, ma_data_source **ppDS)
{
    nca_at *m; CFURLRef url; ExtAudioFileRef f = NULL; OSStatus st;
    AudioStreamBasicDescription fd, cl; UInt32 sz; SInt64 len = 0;
    (void)ud; (void)cfg; (void)alloc;
    if (!nca_ext_is(path, g_atExts)) return MA_INVALID_FILE;
    url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8*)path, (CFIndex)strlen(path), false);
    if (!url) return MA_INVALID_FILE;
    st = ExtAudioFileOpenURL(url, &f);
    CFRelease(url);
    if (st != noErr || !f) return MA_INVALID_FILE;
    sz = sizeof fd;
    if (ExtAudioFileGetProperty(f, kExtAudioFileProperty_FileDataFormat, &sz, &fd) != noErr || fd.mSampleRate < 1 || fd.mChannelsPerFrame < 1) {
        ExtAudioFileDispose(f); return MA_INVALID_FILE;
    }
    memset(&cl, 0, sizeof cl);
    cl.mSampleRate = fd.mSampleRate; cl.mFormatID = kAudioFormatLinearPCM;
    cl.mFormatFlags = kAudioFormatFlagsNativeFloatPacked;
    cl.mChannelsPerFrame = fd.mChannelsPerFrame > 8 ? 8 : fd.mChannelsPerFrame;
    cl.mBitsPerChannel = 32; cl.mFramesPerPacket = 1;
    cl.mBytesPerFrame = cl.mBytesPerPacket = cl.mChannelsPerFrame * 4;
    if (ExtAudioFileSetProperty(f, kExtAudioFileProperty_ClientDataFormat, sizeof cl, &cl) != noErr) { ExtAudioFileDispose(f); return MA_INVALID_FILE; }
    m = (nca_at*)calloc(1, sizeof *m);
    if (!m) { ExtAudioFileDispose(f); return MA_OUT_OF_MEMORY; }
    m->file = f; m->channels = cl.mChannelsPerFrame; m->rate = (ma_uint32)(cl.mSampleRate + 0.5);
    sz = sizeof len;
    if (ExtAudioFileGetProperty(f, kExtAudioFileProperty_FileLengthFrames, &sz, &len) == noErr && len > 0) m->length = (ma_uint64)len;
    {
        ma_data_source_config dc = ma_data_source_config_init();
        dc.vtable = &g_nca_at_ds_vtable;
        if (ma_data_source_init(&dc, &m->ds) != MA_SUCCESS) { ExtAudioFileDispose(f); free(m); return MA_ERROR; }
    }
    *ppDS = (ma_data_source*)m;
    return MA_SUCCESS;
}
static void nca_at_uninit(void *ud, ma_data_source *pDS, const ma_allocation_callbacks *alloc)
{
    nca_at *m = (nca_at*)pDS; (void)ud; (void)alloc;
    ma_data_source_uninit(&m->ds);
    if (m->file) ExtAudioFileDispose(m->file);
    free(m);
}
static ma_decoding_backend_vtable g_nca_at_backend = { NULL, nca_at_init_file, NULL, NULL, nca_at_uninit };
