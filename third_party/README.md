# Third-party sources

Vendored here (single-file libraries, unmodified, licence text in each file):

| Path | Component | Version | Licence |
|---|---|---|---|
| `miniaudio/miniaudio.h` | [miniaudio](https://miniaud.io) - device I/O, MP3/FLAC/WAV decoding (dr_mp3, dr_flac, dr_wav built in) | 0.11.25 | Public domain (Unlicense) or MIT-0 |
| `miniaudio/miniaudio_libopus.{c,h}` | miniaudio libopus decoding backend (from miniaudio `extras/decoders/libopus`) | 0.11.25 | same as miniaudio |
| `stb_vorbis/stb_vorbis.c` | [stb_vorbis](https://github.com/nothings/stb) - Ogg Vorbis decoder | 1.22 | Public domain (Unlicense) or MIT |

Fetched at build time by `scripts/fetch-deps.sh` into `build/deps/` (pinned versions and
SHA-256 checksums in `deps.txt`), built as static libraries and linked into `nc-amp.exe`:

| Component | Version | Licence |
|---|---|---|
| [libogg](https://xiph.org/ogg/) | 1.3.5 | BSD-3-Clause |
| [libopus](https://opus-codec.org) | 1.5.2 | BSD-3-Clause (+ royalty-free patent licences) |
| [opusfile](https://opus-codec.org) | 0.12 | BSD-3-Clause |

See `../THIRD-PARTY-LICENSES.md` for the full licence texts.
