#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
"""Writes the macOS icon (nc-amp.icns) with the same artwork as the Windows icon (mkicon.py):
every size is rendered directly (big sizes with less supersampling to keep memory sane)."""
import sys, os, io, struct
import mkicon
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
# (icns type, pixel size)
TYPES = [(b'icp4', 16), (b'icp5', 32), (b'ic11', 32), (b'ic12', 64), (b'ic07', 128), (b'ic13', 256),
         (b'ic08', 256), (b'ic14', 512), (b'ic09', 512), (b'ic10', 1024)]

def main(out):
    cache = {}
    for _, px in TYPES:
        if px in cache: continue
        mkicon.SS = 16 if px <= 128 else 8 if px <= 256 else 4
        cache[px] = mkicon.render(px)
        mkicon.SS = 16
    chunks = b''
    for t, px in TYPES:
        bio = io.BytesIO(); cache[px].save(bio, 'PNG'); data = bio.getvalue()
        chunks += t + struct.pack('>I', len(data) + 8) + data
    with open(out, 'wb') as f:
        f.write(b'icns' + struct.pack('>I', len(chunks) + 8) + chunks)
    print('wrote', out)

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'nc-amp.icns'))
