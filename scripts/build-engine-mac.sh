#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
#
# Build the audio engine for macOS (arm64 by default) as ONE static library,
# src/engine/mac/lib/libncengine.a, that Free Pascal links into the nc-amp executable:
# ncaudio.c (miniaudio + stb_vorbis + the AudioToolbox AAC backend), opusfile, libopus, libogg.
# Needs Xcode command line tools and CMake. Nothing but system frameworks is linked dynamically.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B="$ROOT/build-mac"; DEPS="$B/deps"; P="$B/prefix"
ARCH=${NCAMP_ARCH:-arm64}
MINVER=${NCAMP_MACOS_MIN:-11.0}
CC=${CC:-clang}
mkdir -p "$DEPS"
grep -v '^#' "$ROOT/third_party/deps.txt" | while read -r name url sum; do
  [ -n "$name" ] || continue
  if [ -f "$DEPS/$name/.ok" ]; then continue; fi
  tgz="$DEPS/$name.tar.gz"
  [ -f "$tgz" ] || { echo "fetching $url"; curl -fL --retry 3 -o "$tgz.part" "$url"; mv "$tgz.part" "$tgz"; }
  echo "$sum  $tgz" | shasum -a 256 -c -
  rm -rf "$DEPS/$name"; tar -xzf "$tgz" -C "$DEPS"; touch "$DEPS/$name/.ok"
done

# -DNDEBUG: no C assertions (an abort() from the engine must never take the player down);
# -ffile-prefix-map: no build-machine paths in the binary
CFLAGS="-arch $ARCH -mmacosx-version-min=$MINVER -O2 -DNDEBUG -fPIC -ffile-prefix-map=$ROOT/=nc-amp/"
for n in ogg opus; do
  case $n in ogg) src=libogg-1.3.5; lib=libogg.a;; opus) src=opus-1.5.2; lib=libopus.a;; esac
  if [ ! -f "$P/lib/$lib" ]; then
    rm -rf "$B/$n"
    EXTRA=""
    [ $n = opus ] && EXTRA="-DOPUS_BUILD_SHARED_LIBRARY=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_DRED=OFF -DOPUS_OSCE=OFF -DOPUS_HARDENING=OFF -DOPUS_FORTIFY_SOURCE=OFF -DOPUS_STACK_PROTECTOR=OFF"
    cmake -S "$DEPS/$src" -B "$B/$n" -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBRARY=OFF -DBUILD_SHARED_LIBS=OFF \
      -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF -DCMAKE_OSX_ARCHITECTURES=$ARCH -DCMAKE_OSX_DEPLOYMENT_TARGET=$MINVER \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_POSITION_INDEPENDENT_CODE=ON -DCMAKE_C_FLAGS="-DNDEBUG -ffile-prefix-map=$ROOT/=nc-amp/" \
      -DCMAKE_PREFIX_PATH="$P" -DCMAKE_INSTALL_PREFIX="$P" $EXTRA
    cmake --build "$B/$n" -j"$(sysctl -n hw.ncpu)" && cmake --install "$B/$n"
  fi
done

O="$DEPS/opusfile-0.12"
E="$ROOT/src/engine"; OBJ="$B/obj"; LIB="$E/mac/lib"
rm -rf "$OBJ"; mkdir -p "$OBJ" "$LIB"
for f in "$E/ncaudio.c" "$O/src/opusfile.c" "$O/src/info.c" "$O/src/internal.c" "$O/src/stream.c"; do
  "$CC" $CFLAGS -c "$f" -o "$OBJ/$(basename "$f" .c).o" \
    -I"$ROOT/third_party/miniaudio" -I"$ROOT/third_party/stb_vorbis" -I"$E" \
    -I"$O/include" -I"$P/include" -I"$P/include/opus"
done
rm -f "$LIB/libncengine.a"
libtool -static -o "$LIB/libncengine.a" "$OBJ"/*.o "$P/lib/libopus.a" "$P/lib/libogg.a"
# report what the engine still needs from the system (libSystem, CoreAudio / AudioToolbox / CoreFoundation)
nm -u "$LIB/libncengine.a" 2>/dev/null | awk '/^ +_/{print $1}' | sort -u > "$B/undef.txt"
nm -g --defined-only "$LIB/libncengine.a" 2>/dev/null | awk 'NF==3{print $3}' | sort -u > "$B/def.txt"
comm -23 "$B/undef.txt" "$B/def.txt" > "$B/needs.txt"
echo "Built the macOS audio engine: $LIB/libncengine.a ($ARCH, macOS >= $MINVER)"
