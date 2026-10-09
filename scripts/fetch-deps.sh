#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
# Download and unpack the pinned libogg / opus / opusfile releases into build/deps/.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
DEPS="$ROOT/build/deps"
mkdir -p "$DEPS"
grep -v '^#' "$ROOT/third_party/deps.txt" | while read -r name url sum; do
  [ -n "$name" ] || continue
  if [ -f "$DEPS/$name/.ok" ]; then continue; fi
  tgz="$DEPS/$name.tar.gz"
  if [ ! -f "$tgz" ]; then
    echo "fetching $url"
    curl -fL --retry 3 -o "$tgz.part" "$url"
    mv "$tgz.part" "$tgz"
  fi
  echo "$sum  $tgz" | sha256sum -c -
  rm -rf "$DEPS/$name"
  tar -xzf "$tgz" -C "$DEPS"
  touch "$DEPS/$name/.ok"
done
