# nc-amp for macOS (Apple Silicon)

The player, playlist, shuffle/resume, settings, skin drawing and LCD rendering are the **same units** as the
Windows build (`src/common/*.pas`, built with `{$IFDEF MSWINDOWS}` / `{$ELSE}` only where the platforms really differ).
The units in this folder replace the Windows-only ones with the same unit names:

| unit | Windows | macOS |
|---|---|---|
| `DpiInit` | per-monitor DPI awareness | nothing to do (layout in points, Retina scale applied at paint) |
| `NcTray` | notification-area icon | menu bar status item (NSStatusItem) |
| `SingleInst` | named mutex + WM_COPYDATA | flock + Unix domain socket |
| `FolderPick` | IFileOpenDialog | NSOpenPanel (multiple folders) |
| `NcTip` | layered tooltip window | borderless NSPanel |
| `NcMac` | - | backing scale, activation, bundled font, sleep/quit notifications |
| `NcTest` | - | test driver, inert unless `NCAMP_TEST_DRIVER=1` |

The audio engine (`src/engine/ncaudio.c`, miniaudio) is shared too; `src/engine/mac/` holds the macOS parts: `ncplat.h` maps the
few Win32 primitives it uses to pthreads, `plat.h` the path/string helpers, `backend_at.h` the AudioToolbox decoder
(AAC/ALAC/AIFF/CAF); `__APPLE__` blocks in `ncaudio.c` add CoreAudio device following.

Build (project `src/mac/nc-amp.lpi`; Xcode command line tools, CMake, Free Pascal 3.2.x for aarch64-darwin, Lazarus 4.x with the Cocoa LCL):

    LAZBUILD=/path/to/lazbuild LAZBUILD_ARGS="--compiler=... --lazarusdir=... --pcp=..." scripts/build-mac.sh

Result: `dist-mac/nc-amp.app` (ad-hoc signed) and `dist-mac/nc-amp-<version>-macos-arm64.zip`.

## Test driver

`NCAMP_TEST_DRIVER=1 NCAMP_LOG=/tmp/nc.log nc-amp.app/Contents/MacOS/nc-amp files...`
reads commands from `/tmp/nc-test-cmd` (see `nctest.pas`): `snap <name>` (PNG of every window),
`click|rclick|drag|move|key`, `windows`. `NCAMP_TEST_SCALE=2` renders and snapshots as on a Retina display.
No Screen Recording or Accessibility permission is needed.
