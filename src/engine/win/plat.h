/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * Windows platform glue of the engine: system headers and the nca_char (UTF-16) helpers
 * (included by ncaudio.c)
 */
#pragma once
#define WIN32_LEAN_AND_MEAN
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mferror.h>
#include <mmdeviceapi.h>
typedef wchar_t nca_char;
#define NCA_T(x) L##x
#define nca_strrchr   wcsrchr
#define nca_stricmp   _wcsicmp
#define nca_strcpy    wcscpy
#define nca_fopen_rb(p) _wfopen((p), L"rb")
#define nca_fseek64   _fseeki64
#define nca_ftell64   _ftelli64
#define nca_decoder_init_file ma_decoder_init_file_w
#define NCA_MAXPATH   (MAX_PATH * 4)
