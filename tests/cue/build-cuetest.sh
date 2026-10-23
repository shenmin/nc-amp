#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
# Build tests/cue/cuetest (Windows: cross compile to build/cuetest/cuetest.exe, needs the engine from
# scripts/build-engine.sh; macOS: native, needs scripts/build-engine-mac.sh). LAZUTILS = Lazarus' components/lazutils
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/build/cuetest"; mkdir -p "$OUT"
LAZUTILS=${LAZUTILS:-/home/box/lazarus/components/lazutils}
if [ "$(uname -s)" = Darwin ]; then
  fpc -O2 -FE"$OUT" -FU"$OUT" -Fu"$ROOT/src/common" -Fu"$LAZUTILS" -Fl"$ROOT/src/engine/mac/lib" "$ROOT/tests/cue/cuetest.pas"
else
  fpc -Twin64 -Px86_64 -O2 -Xs -FE"$OUT" -FU"$OUT" -Fu"$ROOT/src/common" -Fu"$LAZUTILS/lib/x86_64-win64" \
    -Fo"$ROOT/src/engine/win/obj" -Fl"$ROOT/src/engine/win/lib" "$ROOT/tests/cue/cuetest.pas"
fi
echo "built $OUT/cuetest"
