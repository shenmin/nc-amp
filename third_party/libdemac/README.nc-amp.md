# libdemac (Monkey's Audio decoder) in nc-amp

- **What:** libdemac, a decoder for Monkey's Audio (`.ape`) files in portable C, by Dave Chapman and the
  Rockbox project ("demac"). It decodes the format of Matt Ashland's Monkey's Audio, versions 3.97 to 3.99
  (all compression levels from "fast" to "insane"; 8, 16 and 24 bit; mono and stereo).
- **Source:** <https://github.com/Rockbox/rockbox> (`lib/rbcodec/codecs/demac/libdemac`, commit
  `9377ad18c79d274a5abec6ee0cc536f59eb7c019`, 2026-10).
- **Licence:** GNU General Public License, version 2 **or (at your option) any later version**, as stated in
  the header of every source file; the licence text is in `COPYING`. nc-amp is GPL-3.0-or-later, so the
  combination is distributed under GPL-3.0-or-later.
- `README.demac` is the upstream README of the Rockbox `demac` directory.

## Changes made for nc-amp

The files are otherwise unmodified.

- `filter.c`: the x86 MMX/SSE2 vector code is only used when `NCAMP_DEMAC_PORTABLE` is not defined; nc-amp
  defines it, so the plain C vector math in `vector_math_generic.h` is used on every platform.
- `parser.c`: the file-descriptor based header reader (`ape_parseheader`) is compiled out when
  `NCAMP_DEMAC_BUFFER_ONLY` is defined; nc-amp only uses `ape_parseheaderbuf`.

Not included: the CRC code, the ARM / ColdFire / x86 assembler and vector headers, and the standalone
`demac` command line tool. `filter.c` is not compiled on its own: it is `#include`d by the `filter_*.c` files.

## How nc-amp uses it

`src/engine/ncape.c` wraps libdemac: container parsing (including a leading ID3v2 tag), the seek table,
frame-accurate seeking and float output. libdemac keeps its decoder state in static variables, so `ncape.c`
lets several streams exist and restarts a stream at the beginning of its APE frame when another stream used
the decoder in between. `tests/ape/` checks it bit-exactly against the Monkey's Audio SDK decoder.
