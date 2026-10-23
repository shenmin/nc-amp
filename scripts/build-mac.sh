#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
#
# Build nc-amp for macOS (Apple Silicon): dist-mac/nc-amp.app (ad-hoc signed) and nc-amp-<ver>-macos-arm64.zip.
# Needs: Xcode command line tools, CMake, Free Pascal (aarch64-darwin; 3.2.2 needs the fixes_3_2 branch for
# current Xcode linkers) and Lazarus 4.x with the Cocoa LCL built for aarch64-darwin.
# Environment: LAZBUILD (default: lazbuild), LAZBUILD_ARGS (e.g. --lazarusdir=... --pcp=... --compiler=...).
#
# Sources: src/common (shared Pascal), src/mac (macOS units + project), src/engine (C audio engine).
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n "s/^  APPVERSION = '\(.*\)';/\1/p" "$ROOT/src/common/mainform.pas")
LAZBUILD=${LAZBUILD:-lazbuild}
"$ROOT/scripts/build-engine-mac.sh"

cd "$ROOT/src/mac"
$LAZBUILD $LAZBUILD_ARGS --ws=cocoa --cpu=aarch64 --os=darwin nc-amp.lpi

APP="$ROOT/dist-mac/nc-amp.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/src/mac/bin/nc-amp" "$APP/Contents/MacOS/nc-amp"
sed "s/@VERSION@/$VERSION/g" "$ROOT/src/mac/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/assets/icon/nc-amp.icns" "$ROOT/assets/fonts/IBMPlexMono-Medium.ttf" "$ROOT/LICENSE" "$ROOT/THIRD-PARTY-LICENSES.md" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature ok (ad-hoc)"
ZIP="$ROOT/dist-mac/nc-amp-$VERSION-macos-arm64.zip"
rm -f "$ZIP"
( cd "$ROOT/dist-mac" && ditto -c -k --sequesterRsrc --keepParent nc-amp.app "$ZIP" )
echo "Built $APP and $ZIP"
