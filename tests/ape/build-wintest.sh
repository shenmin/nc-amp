#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
# Build tests/ape/wintest.exe (needs the engine from scripts/build-engine.sh and the win64 cross FPC)
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
mkdir -p "$ROOT/build/wintest"
fpc -Twin64 -Px86_64 -O2 -Xs -FE"$ROOT/build/wintest" -FU"$ROOT/build/wintest" \
  -Fu"$ROOT/src/common" -Fo"$ROOT/src/engine/win/obj" -Fl"$ROOT/src/engine/win/lib" "$ROOT/tests/ape/wintest.pas"
echo "built $ROOT/build/wintest/wintest.exe"
