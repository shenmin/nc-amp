#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
#
# Build nc-amp for macOS (Apple Silicon): dist-mac/nc-amp.app (ad-hoc signed) and nc-amp-<ver>-macos-arm64.zip.
# Needs: Xcode command line tools, CMake, Free Pascal (aarch64-darwin; 3.2.2 needs the fixes_3_2 branch for
# current Xcode linkers) and Lazarus 4.x with the Cocoa LCL built for aarch64-darwin.
# Environment: LAZBUILD (default: lazbuild), LAZBUILD_ARGS (e.g. --lazarusdir=... --pcp=... --compiler=...).
#
# The shared sources in src/ are compiled unchanged; src/mac/ holds the macOS replacements of the
# Windows-only units (same unit names), overlaid in a staging copy so the Windows tree is untouched.
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -n "s/^  APPVERSION = '\(.*\)';/\1/p" "$ROOT/src/mainform.pas")
LAZBUILD=${LAZBUILD:-lazbuild}
"$ROOT/scripts/build-engine-mac.sh"

ST="$ROOT/build-mac/src"
rm -rf "$ST"; mkdir -p "$ST"
for f in nc-amp.lpr mainform.pas mainform.lfm ncaudio.pas tagreader.pas titlefont.pas titleglyphs.inc; do cp "$ROOT/src/$f" "$ST/"; done
cp "$ROOT"/src/mac/*.pas "$ROOT/src/mac/nc-amp.lpi" "$ST/"
ln -s "$ROOT/src/engine" "$ST/engine"
cd "$ST"
$LAZBUILD $LAZBUILD_ARGS --ws=cocoa --cpu=aarch64 --os=darwin nc-amp.lpi

APP="$ROOT/dist-mac/nc-amp.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ST/bin/nc-amp" "$APP/Contents/MacOS/nc-amp"
sed "s/@VERSION@/$VERSION/g" "$ROOT/src/mac/Info.plist" > "$APP/Contents/Info.plist"
cp "$ROOT/assets/icon/nc-amp.icns" "$ROOT/assets/fonts/IBMPlexMono-Medium.ttf" "$APP/Contents/Resources/"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP" && echo "signature ok (ad-hoc)"
ZIP="$ROOT/dist-mac/nc-amp-$VERSION-macos-arm64.zip"
rm -f "$ZIP"
( cd "$ROOT/dist-mac" && ditto -c -k --sequesterRsrc --keepParent nc-amp.app "$ZIP" )
echo "Built $APP and $ZIP"
