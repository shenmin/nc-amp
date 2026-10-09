#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
#
# Cross-build nc-amp.exe (Windows x64) on Linux.
# Needs: MinGW-w64 (x86_64-w64-mingw32-gcc, -windres), CMake, curl,
#        Free Pascal 3.2.2 with the x86_64-win64 cross RTL and Lazarus 4.x (lazbuild).
# Output: dist/nc-amp.exe (single self-contained file; the engine DLL is embedded).
set -e
ROOT=$(cd "$(dirname "$0")" && pwd)
"$ROOT/scripts/build-engine.sh"
cd "$ROOT/src"
x86_64-w64-mingw32-windres --preprocessor=cpp -O res -i ncamp.rc -o ncamp.res
lazbuild --os=win64 --cpu=x86_64 --ws=win32 nc-amp.lpi
mkdir -p "$ROOT/dist"
cp bin/nc-amp.exe "$ROOT/dist/nc-amp.exe"
echo "Built dist/nc-amp.exe"
