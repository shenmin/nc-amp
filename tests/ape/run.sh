#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
#
# Test the APE reader (src/engine/ncape.c + third_party/libdemac) against reference decodes.
# Usage: tests/ape/run.sh <dir with pairs name.ape + name.wav>
# The .ape files can be made with the Monkey's Audio command line tool (mac in.wav out.ape -c2000);
# the reference WAV is its own decode (mac out.ape ref.wav -d).
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
DIR=${1:?directory with name.ape + name.wav pairs}
OUT=${TMPDIR:-/tmp}/ncape_test.$$
D=$ROOT/third_party/libdemac
cc -O2 -Wall -DNCAMP_DEMAC_PORTABLE -DNCAMP_DEMAC_BUFFER_ONLY -I"$D" -I"$ROOT/src/engine" -o "$OUT" \
  "$ROOT/tests/ape/ncape_test.c" "$ROOT/src/engine/ncape.c" \
  "$D"/decoder.c "$D"/entropy.c "$D"/filter_*.c "$D"/parser.c "$D"/predictor.c -lm
rc=0
for a in "$DIR"/*.ape; do "$OUT" "$a" "${a%.ape}.wav" || rc=1; done
rm -f "$OUT"
exit $rc
