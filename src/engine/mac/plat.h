/* SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright (C) 2026 Shen Min
 *
 * macOS platform glue of the engine: Win32 primitive shims and the nca_char (UTF-8) helpers
 * (included by ncaudio.c)
 */
#pragma once
#include "ncplat.h"
#include <strings.h>
#include <wchar.h>
#include <wctype.h>
#include <ctype.h>
typedef wchar_t WCHAR;
typedef char nca_char;
#define NCA_T(x) x
#define DEVICE_STATE_ACTIVE 1
#define nca_strrchr   strrchr
#define nca_stricmp   strcasecmp
#define nca_strcpy    strcpy
#define nca_fopen_rb(p) fopen((p), "rb")
#define nca_fseek64   fseeko
#define nca_ftell64   ftello
#define nca_decoder_init_file ma_decoder_init_file
#define NCA_MAXPATH   4096
