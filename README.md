# nc-amp

English | [简体中文](README.zh-CN.md)

nc-amp - a native Free Pascal/Lazarus music player for Windows (64-bit) and macOS (Apple Silicon) with a classic Winamp-style look.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/shenmin/nc-amp)](https://github.com/shenmin/nc-amp/releases)
[![Platform: Windows x64 | macOS arm64](https://img.shields.io/badge/platform-Windows%20x64%20%7C%20macOS%20arm64-0078d6.svg)](https://github.com/shenmin/nc-amp/releases)
[![Made with Lazarus](https://img.shields.io/badge/Lazarus%20%2F%20Free%20Pascal-Pascal-orange.svg)](https://www.lazarus-ide.org)

![nc-amp screenshot](docs/nc-amp-screenshot.png)

## Features

- **Windows (64-bit) and macOS (Apple Silicon)** from one code base: the same player, skin and shortcuts on both.
- **Single portable program:** one exe on Windows x64, one self-contained app on macOS - no installer, no extra files.
- **Formats:** MP3, FLAC, APE (Monkey's Audio), WAV, Ogg Vorbis, Opus, M4A / AAC (AAC via the system decoder: Windows Media Foundation, macOS AudioToolbox, which also plays ALAC, AIFF and CAF on macOS); CUE sheets (`.cue`) for album images; playlists in M3U / M3U8.
- **CUE sheets:** add a `.cue` file (Add files, drag and drop, folder scan, command line, Finder / Explorer open) and every track of the sheet becomes its own playlist row, titled `performer - title` from the sheet, with its own length, seek bar and auto-advance. Works with a CUE for FLAC, APE, WAV, MP3 and other files, several `FILE` entries per sheet, relative paths, and sheets in UTF-8 (with or without BOM), UTF-16 or GBK / GB18030 (Chinese sheets). A folder scan skips an audio file that a CUE in the folder splits into tracks.
- **Save and load playlists:** *Save playlist...* / *Load playlist...* (right-click menu and the playlist's ADD menu) write and read standard `.m3u8` (UTF-8) files, CUE tracks included; paths below the playlist's folder are stored relative to it.
- **Drop and play:** drop files or folders (scanned recursively) on either window; the list plays at once.
- **Always shuffle + repeat:** every track plays once per round, then the list is reshuffled; a new round never starts with the track that just ended.
- **Classic two-window layout:** gunmetal skin with a sage LCD, real-time FFT spectrum, seek, volume and balance, bitrate / sample rate / stereo readouts; separate playlist that docks, snaps and resizes.
- **Shade mode** for both windows (slim bars with mini transport controls; the main bar also has a volume slider), pixel-aligned at every DPI.
- **High DPI:** per-monitor-v2 on Windows (crisp at 100 % - 250 %, rescales when moved between monitors), Retina rendering on macOS; extra size option 1x / 1.5x / 2x.
- **Unicode everywhere:** Chinese file names and tags (ID3v1 GBK, ID3v2, Vorbis comments, APEv2, MP4).
- **Tray / menu bar app:** no taskbar button (Windows: tray icon) or Dock icon (macOS: menu bar status item), both with a native menu; single instance (opening files again hands them to the running copy).
- **100 % open source:** GPL-3.0-or-later, audio engine built only from open-source components.

## Download

Get the zip for your system from [Releases](https://github.com/shenmin/nc-amp/releases):

| System | File | Needs |
|---|---|---|
| Windows | `nc-amp-2.1.0-win64.zip` (contains `nc-amp.exe`) | Windows 10 / 11, 64-bit |
| macOS | `nc-amp-2.1.0-macos-arm64.zip` (contains `nc-amp.app`) | macOS 11 or later on Apple Silicon (M1 and newer) |

**Windows:** unzip and run `nc-amp.exe`. It is not code-signed, so SmartScreen may say "Windows protected your PC" the first time: click *More info* → *Run anyway*.

**macOS:** unzip and move `nc-amp.app` anywhere (for example to Applications). The app is signed ad hoc, not notarised, so Gatekeeper may refuse the first launch ("cannot be opened because the developer cannot be verified"): right-click the app and choose *Open* (then *Open* again), or remove the quarantine flag once in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/nc-amp.app
```

nc-amp has no Dock icon and no menu bar of its own on macOS: use its menu bar status item (left click shows / hides the windows, right click opens the playback menu) or the right-click menu on the player.

## Usage

- Drop music files or folders onto the window, or press **L** / use the eject button.
- Click the time to switch elapsed / remaining; click the spectrum to turn it on / off.
- Double-click the title bar (or the triangle glyph) to shade / unshade a window.
- Resize the docked playlist to about the main window's height and it locks to it exactly.
- Right-click anywhere for size, playlist, visualisation, add files / folder, save / load playlist, info and exit. *Load playlist...* replaces the current list (it starts playing only if the list was empty); dropping a `.m3u` / `.m3u8` file adds its tracks instead.
- Left-click the tray icon (Windows) or the menu bar icon (macOS) to show / hide; right-click it for playback controls.
- Settings are stored in `%LOCALAPPDATA%\nc-amp\` on Windows and in `~/Library/Application Support/nc-amp/` on macOS (`nc-amp.ini`, `playlist.m3u8`).

## Keyboard shortcuts

| Key | Action |
|---|---|
| Z / X / C / V / B | Previous / Play / Pause / Stop / Next |
| L | Open files |
| ← / → | Seek -5 s / +5 s |
| ↑ / ↓, Home / End | Move playlist selection |
| Enter | Play selected track |
| Del | Remove selected tracks |
| Ctrl+A | Select all (the Control key, also on macOS) |

## Build from source

The sources are split by platform (see the layout below). The Windows exe is cross-built on Linux (Debian / Ubuntu shown); it can also be built on Windows with MSYS2 + Lazarus. The macOS app is built on a Mac.

### Windows (64-bit)

Requirements:

- Free Pascal 3.2.2 with the `x86_64-win64` cross RTL (e.g. `make crossinstall OS_TARGET=win64 CPU_TARGET=x86_64` in the FPC sources, or fpcupdeluxe) and Lazarus 4.x (`lazbuild`)
- MinGW-w64 (`x86_64-w64-mingw32-gcc`, `x86_64-w64-mingw32-windres`), CMake, curl

```sh
sudo apt install fpc lazarus gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 cmake curl
git clone https://github.com/shenmin/nc-amp.git
cd nc-amp
./build.sh                  # -> dist/nc-amp.exe
scripts/package-win.sh      # -> dist/nc-amp-<version>-win64.zip (optional)
```

`build.sh` does three things (set `LAZBUILD_ARGS`, e.g. `--lazarusdir=/path/to/lazarus`, if `lazbuild` needs it):

1. `scripts/fetch-deps.sh` downloads the pinned libogg, libopus and opusfile releases (checked against the SHA-256 sums in `third_party/deps.txt`).
2. `scripts/build-engine.sh` builds them as static libraries and compiles the audio engine `src/engine/ncaudio.c` (with miniaudio and stb_vorbis from `third_party/`), the APE reader `src/engine/ncape.c` and libdemac into object files. It then picks the objects the engine needs from those libraries and from the MinGW runtime, and lists them in `src/engine/win/objs.inc`.
3. `windres` packs the manifest and LCD font into `src/win/ncamp.res`, then `lazbuild` builds `src/win/nc-amp.lpi`. Free Pascal links the engine objects straight into the exe, so the result is a single file that writes nothing to disk.

Once `src/engine/win/objs.inc` and `src/win/ncamp.res` exist you can also open `src/win/nc-amp.lpi` in the Lazarus IDE.

### macOS (Apple Silicon)

Requirements: Xcode command line tools, CMake, curl, Free Pascal 3.2.2 for `aarch64-darwin` (3.2.2 needs the `fixes_3_2` branch to work with current Xcode linkers) and Lazarus 4.x with the Cocoa LCL built for `aarch64-darwin`.

```sh
git clone https://github.com/shenmin/nc-amp.git
cd nc-amp
LAZBUILD=/path/to/lazbuild LAZBUILD_ARGS="--lazarusdir=/path/to/lazarus" scripts/build-mac.sh
# -> dist-mac/nc-amp.app (ad-hoc signed) and dist-mac/nc-amp-<version>-macos-arm64.zip
```

`scripts/build-mac.sh` runs `scripts/build-engine-mac.sh` (the same engine sources plus libogg / libopus / opusfile, as one static library `src/engine/mac/lib/libncengine.a`), builds `src/mac/nc-amp.lpi` with `lazbuild`, assembles and ad-hoc signs the `.app` and zips it. More notes: [src/mac/README.md](src/mac/README.md).

### Repository layout

```
src/common/     Pascal units shared by both platforms (player window, audio binding, tags, CUE and M3U parsers, fonts)
src/win/        Windows units, Lazarus project (nc-amp.lpi), manifest, icon, resources
src/mac/        macOS units, Lazarus project (nc-amp.lpi), Info.plist, test driver
src/engine/     audio engine (C): miniaudio + stb_vorbis + opusfile + libdemac (APE); ncape.c is the APE reader
src/engine/win/ Windows parts: Media Foundation (AAC) backend, C runtime stubs, platform header
src/engine/mac/ macOS parts: AudioToolbox (AAC / ALAC / AIFF / CAF) backend, platform headers
third_party/    vendored libraries (miniaudio, stb_vorbis, libdemac) and the pinned dependency list
tests/ape/      APE decoder tests (bit-exact against the Monkey's Audio decoder)
tests/cue/      CUE support tests (parser + engine, with generated test material)
assets/fonts/   IBM Plex Mono, Audiowide (OFL) and the title-glyph generator
assets/icon/    app icon (.ico, .icns) and its generator scripts
docs/           screenshots
scripts/        build helpers (engine, macOS app, Windows zip)
```

## Credits

- Audio: [miniaudio](https://miniaud.io) (with dr_mp3 / dr_flac / dr_wav), [stb_vorbis](https://github.com/nothings/stb), [libopus, opusfile and libogg](https://opus-codec.org), [libdemac](https://github.com/Rockbox/rockbox/tree/master/lib/rbcodec/codecs/demac) from Rockbox for APE (GPL-2.0-or-later; Monkey's Audio is by Matt Ashland), Windows Media Foundation / macOS AudioToolbox for AAC.
- Fonts: [IBM Plex Mono](https://github.com/IBM/plex) (LCD text and icon) and [Audiowide](https://fonts.google.com/specimen/Audiowide) (title), both SIL OFL 1.1.
- Built with [Free Pascal](https://www.freepascal.org) and [Lazarus](https://www.lazarus-ide.org).
- Look inspired by Winamp 2.x. nc-amp is not affiliated with Winamp.

Bundled third-party code and its licences: miniaudio (public domain / MIT-0), stb_vorbis (MIT / public domain), libogg, libopus and opusfile (BSD-3-Clause), libdemac (GPL-2.0-or-later, used under GPL-3.0-or-later), IBM Plex Mono and Audiowide (SIL OFL 1.1); Free Pascal and Lazarus libraries are LGPL with the static-linking exception. Full licence texts: [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) (also in the Windows zip and inside `nc-amp.app`).

## License

Copyright (C) 2026 Shen Min ([https://github.com/shenmin](https://github.com/shenmin))

nc-amp is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE).
