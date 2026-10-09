#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
# Build the audio engine src/engine/ncaudio.dll (Win64) with MinGW-w64:
# static libogg + libopus (CMake), opusfile, miniaudio, stb_vorbis.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B="$ROOT/build"; DEPS="$B/deps"; P="$B/prefix"
CC=${CC:-x86_64-w64-mingw32-gcc-posix}
command -v "$CC" >/dev/null 2>&1 || CC=x86_64-w64-mingw32-gcc
CXX=$(echo "$CC" | sed 's/gcc/g++/')
"$ROOT/scripts/fetch-deps.sh"

cat > "$B/mingw.cmake" <<EOT
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
EOT

if [ ! -f "$P/lib/libogg.a" ]; then
  cmake -S "$DEPS/libogg-1.3.5" -B "$B/libogg" -DCMAKE_TOOLCHAIN_FILE="$B/mingw.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF \
    -DCMAKE_INSTALL_PREFIX="$P"
  cmake --build "$B/libogg" -j"$(nproc)" && cmake --install "$B/libogg"
fi
if [ ! -f "$P/lib/libopus.a" ]; then
  cmake -S "$DEPS/opus-1.5.2" -B "$B/opus" -DCMAKE_TOOLCHAIN_FILE="$B/mingw.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DOPUS_BUILD_SHARED_LIBRARY=OFF -DOPUS_BUILD_TESTING=OFF \
    -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_DRED=OFF -DOPUS_OSCE=OFF -DCMAKE_INSTALL_PREFIX="$P"
  cmake --build "$B/opus" -j"$(nproc)" && cmake --install "$B/opus"
fi

O="$DEPS/opusfile-0.12"
"$CC" -O2 -shared -o "$ROOT/src/engine/ncaudio.dll" "$ROOT/src/engine/ncaudio.c" \
  "$O/src/opusfile.c" "$O/src/info.c" "$O/src/internal.c" "$O/src/stream.c" \
  -I"$ROOT/third_party/miniaudio" -I"$ROOT/third_party/stb_vorbis" \
  -I"$O/include" -I"$P/include" -I"$P/include/opus" -L"$P/lib" -lopus -logg \
  -lmfuuid -lole32 -luuid -lwinmm -static -static-libgcc -s
echo "Built src/engine/ncaudio.dll"
