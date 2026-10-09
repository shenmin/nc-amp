<p align="right">English | <a href="README.zh-CN.md">简体中文</a></p>

# nc-amp

nc-amp - a native Free Pascal/Lazarus music player for Windows with a classic Winamp-style look.

[![License: GPL-3.0](https://img.shields.io/badge/license-GPL--3.0-blue.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/shenmin/nc-amp)](https://github.com/shenmin/nc-amp/releases)
[![Platform: Windows](https://img.shields.io/badge/platform-Windows%20x64-0078d6.svg)](https://github.com/shenmin/nc-amp/releases)
[![Made with Lazarus](https://img.shields.io/badge/Lazarus%20%2F%20Free%20Pascal-Pascal-orange.svg)](https://www.lazarus-ide.org)

![nc-amp screenshot](docs/screenshot.png)

## Features

- **Single portable exe** for Windows x64 - no installer, no extra files.
- **Formats:** MP3, FLAC, WAV, Ogg Vorbis, Opus, M4A / AAC (AAC via the Windows Media Foundation decoder).
- **Drop and play:** drop files or folders (scanned recursively) on either window; the list plays at once.
- **Always shuffle + repeat:** every track plays once per round, then the list is reshuffled; a new round never starts with the track that just ended.
- **Classic two-window layout:** gunmetal skin with a sage LCD, real-time FFT spectrum, seek, volume and balance, bitrate / sample rate / stereo readouts; separate playlist that docks, snaps and resizes.
- **Shade mode** for both windows (slim bars with mini transport controls), pixel-aligned at every DPI.
- **Per-monitor-v2 high DPI:** crisp at 100 % - 250 %, rescales when moved between monitors; extra size option 1x / 1.5x / 2x.
- **Unicode everywhere:** Chinese file names and tags (ID3v1 GBK, ID3v2, Vorbis comments, MP4).
- **Tray app:** no taskbar button; tray icon with native menu; single instance (opening files again hands them to the running copy).
- **100 % open source:** GPL-3.0-or-later, audio engine built only from open-source components.

## Download

Get `nc-amp.exe` from [Releases](https://github.com/shenmin/nc-amp/releases) and run it - Windows 10 / 11 x64.

The exe is not code-signed, so SmartScreen may say "Windows protected your PC" the first time: click *More info* → *Run anyway*.

## Usage

- Drop music files or folders onto the window, or press **L** / use the eject button.
- Click the time to switch elapsed / remaining; click the spectrum to turn it on / off.
- Double-click the title bar (or the triangle glyph) to shade / unshade a window.
- Resize the docked playlist to about the main window's height and it locks to it exactly.
- Right-click anywhere for size, playlist, visualisation, add files / folder, info and exit.
- Left-click the tray icon to show / hide; right-click it for playback controls.
- Settings are stored in `%LOCALAPPDATA%\nc-amp\` (`nc-amp.ini`, `playlist.m3u8`).

## Keyboard shortcuts

| Key | Action |
|---|---|
| Z / X / C / V / B | Previous / Play / Pause / Stop / Next |
| L | Open files |
| ← / → | Seek -5 s / +5 s |
| ↑ / ↓, Home / End | Move playlist selection |
| Enter | Play selected track |
| Del | Remove selected tracks |
| Ctrl+A | Select all |

## Build from source

nc-amp is cross-built on Linux (Debian / Ubuntu shown); it can also be built on Windows with MSYS2 + Lazarus.

Requirements:

- Free Pascal 3.2.2 with the `x86_64-win64` cross RTL (e.g. `make crossinstall OS_TARGET=win64 CPU_TARGET=x86_64` in the FPC sources, or fpcupdeluxe) and Lazarus 4.x (`lazbuild`)
- MinGW-w64 (`x86_64-w64-mingw32-gcc`, `x86_64-w64-mingw32-windres`), CMake, curl

```sh
sudo apt install fpc lazarus gcc-mingw-w64-x86-64 binutils-mingw-w64-x86-64 cmake curl
git clone https://github.com/shenmin/nc-amp.git
cd nc-amp
./build.sh            # -> dist/nc-amp.exe
```

`build.sh` does three things:

1. `scripts/fetch-deps.sh` downloads the pinned libogg, libopus and opusfile releases (checked against the SHA-256 sums in `third_party/deps.txt`).
2. `scripts/build-engine.sh` builds them as static libraries and compiles the audio engine `src/engine/ncaudio.c` together with miniaudio and stb_vorbis (`third_party/`) into `src/engine/ncaudio.dll`.
3. `windres` packs the manifest, engine and LCD font into `src/ncamp.res`, then `lazbuild` builds `src/nc-amp.lpi`. The engine DLL is embedded in the exe and unpacked to `%TEMP%` at start-up, so the result is a single file.

Once `src/engine/ncaudio.dll` and `src/ncamp.res` exist you can also open `src/nc-amp.lpi` in the Lazarus IDE.

Repository layout:

```
src/            Pascal sources, Lazarus project, resources
src/engine/     audio engine (C): miniaudio + stb_vorbis + opusfile + Media Foundation
third_party/    vendored single-file libraries and pinned dependency list
assets/fonts/   IBM Plex Mono, Audiowide (OFL) and the title-glyph generator
assets/icon/    app icon and its generator script
docs/           screenshots
scripts/        build helpers
```

## Credits

- Audio: [miniaudio](https://miniaud.io) (with dr_mp3 / dr_flac / dr_wav), [stb_vorbis](https://github.com/nothings/stb), [libopus, opusfile and libogg](https://opus-codec.org), Windows Media Foundation for AAC.
- Fonts: [IBM Plex Mono](https://github.com/IBM/plex) (LCD text and icon) and [Audiowide](https://fonts.google.com/specimen/Audiowide) (title), both SIL OFL 1.1.
- Built with [Free Pascal](https://www.freepascal.org) and [Lazarus](https://www.lazarus-ide.org).
- Look inspired by Winamp 2.x. nc-amp is not affiliated with Winamp.

Full licence texts: [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

## License

Copyright (C) 2026 Shen Min ([https://github.com/shenmin](https://github.com/shenmin))

nc-amp is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE).
