#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
#
# Package dist/nc-amp.exe (from ./build.sh) as dist/nc-amp-<version>-win64.zip:
# nc-amp-<version>/{nc-amp.exe, README.md, README.zh-CN.md, LICENSE, THIRD-PARTY-LICENSES.md}
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n "s/^  APPVERSION = '\(.*\)';/\1/p" "$ROOT/src/common/mainform.pas")
D="$ROOT/dist/nc-amp-$VERSION"
rm -rf "$D"; mkdir -p "$D"
cp "$ROOT/dist/nc-amp.exe" "$ROOT/README.md" "$ROOT/README.zh-CN.md" "$ROOT/LICENSE" "$ROOT/THIRD-PARTY-LICENSES.md" "$D/"
( cd "$ROOT/dist" && rm -f "nc-amp-$VERSION-win64.zip" && python3 -m zipfile -c "nc-amp-$VERSION-win64.zip" "nc-amp-$VERSION" )
rm -rf "$D"
echo "Built $ROOT/dist/nc-amp-$VERSION-win64.zip"
