#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
# Build the audio engine (Win64) with MinGW-w64 as objects + static libraries that
# Free Pascal links into nc-amp.exe (src/engine/win/obj, src/engine/win/lib):
# static libogg + libopus (CMake), opusfile, miniaudio, stb_vorbis, libdemac (APE).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
B="$ROOT/build"; DEPS="$B/deps"; P="$B/prefix"
CC=${CC:-x86_64-w64-mingw32-gcc-posix}
command -v "$CC" >/dev/null 2>&1 || CC=x86_64-w64-mingw32-gcc
CXX=$(echo "$CC" | sed 's/gcc/g++/')
LD=x86_64-w64-mingw32-ld; STRIP=x86_64-w64-mingw32-strip; NM=x86_64-w64-mingw32-nm
AR=x86_64-w64-mingw32-ar; OBJDUMP=x86_64-w64-mingw32-objdump
"$ROOT/scripts/fetch-deps.sh"

# Flags for everything that ends up in nc-amp.exe. The engine is linked by Free Pascal's
# internal linker, and MinGW's start-up code never runs:
#  -mcmodel=small: address data directly instead of through COMDAT ".refptr" stubs, which
#     Free Pascal's linker cannot merge across objects (internal error 200603061)
#  -fno-reorder-blocks-and-partition: no separate .text.unlikely cold sections
#  stack protector / fortify off (opus): nothing would initialise the stack guard
#  -DNDEBUG, opus hardening off: no C runtime assertion (a modal "Assertion failed!" dialog from
#     msvcrt) or abort() can come from the engine in a release build
#  -ffile-prefix-map: no build-machine paths in the binary
# NCAMP_ENGINE_ASSERTS=1 builds a test exe with the C assertions left on.
ENGINE_CFLAGS="-mcmodel=small -fno-reorder-blocks-and-partition -ffile-prefix-map=$ROOT/=nc-amp/"
if [ "${NCAMP_ENGINE_ASSERTS:-0}" = 1 ]; then echo "*** engine built WITH assertions (test build) ***"; else ENGINE_CFLAGS="$ENGINE_CFLAGS -DNDEBUG"; fi

cat > "$B/mingw.cmake" <<EOT
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_C_COMPILER $CC)
set(CMAKE_CXX_COMPILER $CXX)
set(CMAKE_RC_COMPILER x86_64-w64-mingw32-windres)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_C_FLAGS_INIT "$ENGINE_CFLAGS")
EOT

if [ ! -f "$P/lib/libogg.a" ] || [ ! -f "$P/lib/.static-engine-2.0.1" ]; then
  rm -rf "$B/libogg"
  cmake -S "$DEPS/libogg-1.3.5" -B "$B/libogg" -DCMAKE_TOOLCHAIN_FILE="$B/mingw.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF -DINSTALL_DOCS=OFF -DBUILD_TESTING=OFF \
    -DCMAKE_INSTALL_PREFIX="$P"
  cmake --build "$B/libogg" -j"$(nproc)" && cmake --install "$B/libogg"
fi
if [ ! -f "$P/lib/libopus.a" ] || [ ! -f "$P/lib/.static-engine-2.0.1" ]; then
  rm -rf "$B/opus"
  cmake -S "$DEPS/opus-1.5.2" -B "$B/opus" -DCMAKE_TOOLCHAIN_FILE="$B/mingw.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DOPUS_BUILD_SHARED_LIBRARY=OFF -DOPUS_BUILD_TESTING=OFF \
    -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_DRED=OFF -DOPUS_OSCE=OFF \
    -DOPUS_STACK_PROTECTOR=OFF -DOPUS_FORTIFY_SOURCE=OFF -DOPUS_HARDENING=OFF -DCMAKE_INSTALL_PREFIX="$P"
  cmake --build "$B/opus" -j"$(nproc)" && cmake --install "$B/opus"
  touch "$P/lib/.static-engine-2.0.1"
fi

O="$DEPS/opusfile-0.12"
E="$ROOT/src/engine"; W="$E/win"; OBJ="$W/obj"; LIB="$W/lib"
rm -rf "$OBJ" "$LIB"; mkdir -p "$OBJ" "$LIB"
for f in "$E/ncaudio.c" "$W/nccrt.c" "$W/ncguids.c" "$O/src/opusfile.c" "$O/src/info.c" "$O/src/internal.c" "$O/src/stream.c"; do
  "$CC" -O2 $ENGINE_CFLAGS -c "$f" -o "$OBJ/$(basename "$f" .c).o" \
    -I"$ROOT/third_party/miniaudio" -I"$ROOT/third_party/stb_vorbis" -I"$E" \
    -I"$O/include" -I"$P/include" -I"$P/include/opus"
done
# The static libraries the engine needs: libopus, libogg, MinGW's mingwex and libgcc, and the static part of MinGW's libmsvcrt.a (which mixes
# msvcrt.dll imports with static code such as its own sin / cos / pow).
S="$B/engine-static"; rm -rf "$S"; mkdir -p "$S/x"
( cd "$S/x" && "$AR" x "$($CC -print-file-name=libmsvcrt.a)" )
for f in "$S"/x/*.o; do
  if "$OBJDUMP" -h "$f" | grep -q 'idata\$'; then echo "$f" >> "$S/imp.txt"; else echo "$f" >> "$S/static.txt"; fi
done
"$AR" rcs "$S/libmsvcrt_static.a" $(cat "$S/static.txt")
"$AR" rcs "$LIB/libmsvcrt.a" $(cat "$S/imp.txt")              # import-only
for l in libole32.a libkernel32.a; do cp "$($CC -print-file-name=$l)" "$LIB/"; done
ARCHIVES="$P/lib/libopus.a $P/lib/libogg.a \
  $S/libmsvcrt_static.a $($CC -print-file-name=libmingwex.a) $($CC -print-libgcc-file-name)"
# GNU ld decides which archive members are needed; Free Pascal's internal linker then gets
# exactly those as plain objects ({$L}, generated src/engine/win/objs.inc). Letting FPC search the
# archives itself does not work: it searches each library once (the runtime archives reference
# each other), and objects merged with "ld -r" have duplicate section symbols it mislinks.
"$LD" -r -Map "$S/map.txt" -o "$S/check.o" "$OBJ"/*.o --start-group $ARCHIVES --end-group
awk '/^Archive member included/{f=1;next} /^(Discarded|Memory map|Allocating common)/{f=0} f && /^[^ ].*\.a\(/{print $1}' "$S/map.txt" | sort -u > "$S/members.txt"
while read -r m; do
  a=${m%%(*}; o=${m#*(}; o=${o%)}
  n="$(basename "$a" .a)-${o%.obj}"; n="${n%.o}.o"        # CMake names members *.c.obj
  ( cd "$S" && "$AR" x "$a" "$o" && mv "$o" "$OBJ/$n" )
done < "$S/members.txt"
"$STRIP" --strip-debug "$OBJ"/*.o
{ echo "{ generated by scripts/build-engine.sh: the audio engine objects for nc-amp.exe }"
  for f in "$OBJ"/*.o; do echo "{\$L $(basename "$f")}"; done; } > "$W/objs.inc"
# check: everything except kernel32 / ole32 / msvcrt imports resolves statically
"$NM" -u "$S/check.o" | awk '{print $2}' | sed 's/^__imp_//' | sort -u > "$S/undef.txt"
for l in kernel32 ole32 msvcrt; do "$NM" "$LIB/lib$l.a" 2>/dev/null | awk '$2=="I"||$2=="T"{print $3}'; done | sed 's/^__imp_//' | sort -u > "$S/avail.txt"
MISSING=$(comm -23 "$S/undef.txt" "$S/avail.txt")
if [ -n "$MISSING" ]; then echo "unresolved engine symbols: $MISSING" >&2; exit 1; fi
# Free Pascal's linker keeps only one copy of a symbol defined in several objects (e.g. a
# selectany GUID) yet may leave relocations pointing at a dropped copy: refuse duplicates
DUPS=$(for f in "$OBJ"/*.o; do "$NM" -g --defined-only "$f" | awk 'NF==3{print $3}' | sort -u; done | sort | uniq -d)
if [ -n "$DUPS" ]; then echo "engine symbols defined more than once: $DUPS" >&2; exit 1; fi
# no MinGW start-up code runs in nc-amp.exe: refuse constructors, CRT init lists and TLS data
INIT=$(for f in "$OBJ"/*.o; do if "$OBJDUMP" -h "$f" | grep -qE ' \.(ctors|dtors|tls|CRT\$)'; then basename "$f"; fi; done)
if [ -n "$INIT" ]; then echo "engine objects need MinGW start-up code: $INIT" >&2; exit 1; fi
if [ "${NCAMP_ENGINE_ASSERTS:-0}" != 1 ]; then
  # release: no C runtime assertions (msvcrt _assert / _wassert show a modal dialog) ...
  ASRT=$(for f in "$OBJ"/*.o; do if "$NM" -u "$f" | grep -qE ' (__imp_)?_w?assert$'; then basename "$f"; fi; done)
  if [ -n "$ASRT" ]; then echo "engine objects use C assertions (build with -DNDEBUG): $ASRT" >&2; exit 1; fi
  # ... and no build paths (assertion / hardening messages carry __FILE__)
  LEAK=$(for f in "$OBJ"/*.o; do if strings -a "$f" | grep -qF "$ROOT"; then basename "$f"; fi; done)
  if [ -n "$LEAK" ]; then echo "engine objects contain the build path $ROOT: $LEAK" >&2; exit 1; fi
fi
echo "Built the audio engine: $(ls "$OBJ" | wc -l) objects in src/engine/win/obj (src/engine/win/objs.inc)"
