#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
"""nc-amp icon generator: 'nc' rendered from the embedded IBM Plex Mono Medium outlines,
dark ink on LCD sage, slim gunmetal bezel + thin black frame, small spectrum bars.
Every size is rendered directly (no downscaling of a big master) on an integer pixel
grid: frame edges, bars, x-height and baseline are snapped to whole pixels; small sizes
get a contrast curve on the text coverage so the stems stay crisp."""
import sys, os
from PIL import Image, ImageDraw, ImageChops
from fontTools.ttLib import TTFont
from fontTools.pens.recordingPen import DecomposingRecordingPen

HERE = os.path.dirname(os.path.abspath(__file__))
FONT = os.path.join(HERE, '..', 'fonts', 'IBMPlexMono-Medium.ttf')
SIZES = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
SS = 16  # supersampling per pixel

SAGE = (192, 216, 184); SAGE_DK = (176, 200, 168)
INK = (52, 56, 62)
FRAME = (12, 13, 13)
BEZ_TOP = (128, 130, 132); BEZ_BOT = (62, 63, 65); BEZ_HI = (170, 172, 174)

font = TTFont(FONT)
cmap = font.getBestCmap(); gs = font.getGlyphSet()
UPM = font['head'].unitsPerEm; XH = font['OS/2'].sxHeight; ADV = 600

def glyph_polys(ch, steps=12):
    pen = DecomposingRecordingPen(gs); gs[cmap[ord(ch)]].draw(pen)
    polys, cur, start = [], [], None
    def q(p0, p1, p2):
        return [((1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0], (1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]) for t in [i/steps for i in range(1, steps+1)]]
    for op, args in pen.value:
        if op == 'moveTo':
            cur = [args[0]]
        elif op == 'lineTo':
            cur.append(args[0])
        elif op == 'qCurveTo':
            pts = list(args); p0 = cur[-1]
            # TrueType implied on-curve points
            offs, on = pts[:-1], pts[-1]
            for i, c in enumerate(offs):
                nxt = on if i == len(offs)-1 else ((c[0]+offs[i+1][0])/2, (c[1]+offs[i+1][1])/2)
                cur += q(p0, c, nxt); p0 = nxt
        elif op == 'curveTo':
            p0 = cur[-1]; c1, c2, p3 = args
            for i in range(1, steps+1):
                t = i/steps
                cur.append(((1-t)**3*p0[0]+3*(1-t)**2*t*c1[0]+3*(1-t)*t*t*c2[0]+t**3*p3[0],
                            (1-t)**3*p0[1]+3*(1-t)**2*t*c1[1]+3*(1-t)*t*t*c2[1]+t**3*p3[1]))
        elif op in ('closePath', 'endPath'):
            if cur: polys.append(cur); cur = []
    return polys

POLYS = {c: glyph_polys(c) for c in 'nc'}

def layout(s):
    """integer pixel layout for size s"""
    if s <= 16:   bez, frm, rad = 1, 1, 2.5
    elif s <= 24: bez, frm, rad = 1, 1, 3.5
    elif s <= 32: bez, frm, rad = 2, 1, 5
    elif s <= 48: bez, frm, rad = 2, 1, 0.16*s
    else:         bez, frm, rad = round(0.05*s), max(1, round(0.018*s)), 0.16*s
    face = s - 2*(bez+frm)
    return bez, frm, rad, face

def text_metrics(s, face):
    # x-height in whole pixels, chosen so 'nc' fits the face width with a little air
    pad = 1 if s <= 24 else max(2, round(face*0.08))
    ink_units = ADV + 527 - 84 - 60          # 'nc' ink width with slightly tightened tracking
    xh = int((face - 2*pad) * XH / ink_units)
    if s <= 16: xh = min(xh, 5)
    elif s <= 20: xh = min(xh, 6)
    elif s <= 24: xh = min(xh, 7)
    return xh, pad

def bars_for(s):
    if s <= 24: return [0.55, 1.0, 0.7, 0.9]           # 4 crisp 1-px bars
    if s <= 40: return [0.5, 0.85, 1.0, 0.65, 0.9, 0.6, 0.8]
    return [0.45, 0.75, 1.0, 0.6, 0.9, 0.55, 0.8, 0.5, 0.7]

def render(s):
    W = s*SS
    bez, frm, rad, face = layout(s)
    img = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    # bezel: vertical gradient through a rounded-rect mask
    grad = Image.new('RGBA', (W, W))
    gd = ImageDraw.Draw(grad)
    for y in range(W):
        t = y/(W-1)
        gd.line([(0, y), (W, y)], fill=tuple(int(BEZ_TOP[i]+(BEZ_BOT[i]-BEZ_TOP[i])*t) for i in range(3))+(255,))
    mask = Image.new('L', (W, W), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, W-1, W-1], radius=rad*SS, fill=255)
    img.paste(grad, (0, 0), mask)
    if s >= 48:   # 1-px top highlight on the bezel
        hl = Image.new('L', (W, W), 0); hd = ImageDraw.Draw(hl)
        hd.rounded_rectangle([0, 0, W-1, W-1], radius=rad*SS, fill=255)
        hd.rounded_rectangle([0, SS, W-1, W-1+SS], radius=rad*SS, fill=0)
        img.paste(Image.new('RGBA', (W, W), BEZ_HI+(255,)), (0, 0), hl)
    o = bez*SS
    r2 = max(0.0, rad - bez)
    d.rounded_rectangle([o, o, W-1-o, W-1-o], radius=r2*SS, fill=FRAME+(255,))
    o2 = (bez+frm)*SS
    r3 = max(0.0, r2 - frm*0.7)
    if s <= 24: r3 = 0.0     # square face corners at small sizes: crisper
    # sage face with a faint gradient
    fm = Image.new('L', (W, W), 0)
    ImageDraw.Draw(fm).rounded_rectangle([o2, o2, W-1-o2, W-1-o2], radius=r3*SS, fill=255)
    fg = Image.new('RGBA', (W, W)); fd = ImageDraw.Draw(fg)
    for y in range(o2, W-o2):
        t = (y-o2)/max(1, W-2*o2-1)
        fd.line([(o2, y), (W-o2, y)], fill=tuple(int(SAGE[i]+(SAGE_DK[i]-SAGE[i])*t*0.6) for i in range(3))+(255,))
    img.paste(fg, (0, 0), fm)

    fx0 = bez+frm; fy0 = bez+frm; fy1 = s-bez-frm        # face box in px
    # per-size vertical rhythm (px): top pad, x-height font px, gap, bar height, bar w, bar gap, bars
    # small sizes: (top pad, x-height, gap, bar h, bar w, bar gap, bar heights, n width, c width, letter gap, stem, h-stroke)
    SMALL = {16: (1, 6, 1, 3, 1, 1, [2, 3, 1, 2], 5, 4, 1, 1, 1),
             20: (2, 7, 2, 3, 1, 1, [2, 3, 1, 2], 6, 6, 2, 1, 1),
             24: (2, 9, 2, 4, 2, 1, [2, 4, 1, 3], 7, 7, 2, 2, 2),
             32: (3, 12, 3, 5, 2, 1, [2, 4, 5, 3, 4, 2, 3], 10, 10, 3, 3, 2),
             40: (5, 15, 3, 5, 2, 2, [2, 4, 5, 3, 5, 3, 4], 13, 13, 3, 3, 3),
             48: (6, 18, 4, 6, 2, 2, [3, 4, 6, 4, 5, 3, 5, 3, 4], 15, 15, 4, 4, 3),
             64: (8, 24, 5, 8, 3, 2, [4, 6, 8, 5, 7, 4, 6, 4, 6], 20, 20, 5, 5, 4)}
    if s in SMALL:
        tpad, xhp, gap_tb, bh, bw, bgap, hs, wn, wc, gap_x, sw, ah = SMALL[s]
    else:
        tpad = gap_tb = None
        bw = max(1, round(face*0.045)); bgap = max(1, round(face*0.04)); bh = round(face*0.14)
        hs = [max(1, round(bh*h)) for h in bars_for(s)]
    # ---- 'nc' ----
    tm = Image.new('L', (W, W), 0)
    if s in SMALL:
        # pixel hinting of the real Plex Mono Medium outlines: piecewise-linear maps put
        # every stem edge, the x-height, the arch / bowl strokes and the baseline exactly
        # on pixel boundaries (what a TrueType hinter does), then 16x16 supersampling
        import numpy as np
        def pl(v, ks, vs):
            if v <= ks[0]: return vs[0] + (v-ks[0])*(vs[1]-vs[0])/(ks[1]-ks[0])
            for i in range(1, len(ks)):
                if v <= ks[i]: return vs[i-1] + (v-ks[i-1])*(vs[i]-vs[i-1])/(ks[i]-ks[i-1])
            return vs[-1] + (v-ks[-1])*(vs[-1]-vs[-2])/(ks[-1]-ks[-2])
        total = wn + gap_x + wc
        x0 = fx0 + (face - total + 1)//2
        base = fy0 + tpad + xhp
        maps = {'n': ([84, 193, 412, 521], [0, sw, wn-sw, wn], [0, 438, 528], [0, xhp-ah, xhp]),
                'c': ([74, 188, 527], [0, sw, wc], [-12, 80, 438, 528], [0, ah, xhp-ah, xhp])}
        acc = np.zeros((W, W), dtype=np.uint8)
        for ch, ox in (('n', x0), ('c', x0 + wn + gap_x)):
            kx, vx, ky, vy = maps[ch]
            for poly in POLYS[ch]:
                pts = [((ox + pl(x, kx, vx))*SS, (base - pl(y, ky, vy))*SS) for x, y in poly]
                layer = Image.new('L', (W, W), 0)
                ImageDraw.Draw(layer).polygon(pts, fill=255)
                acc ^= np.array(layer)
        tm = Image.fromarray(acc)
        small_txt = None
        bars_bottom = base + gap_tb + bh
    else:
        xh, pad = text_metrics(s, face)
        sc = xh / XH
        track = -60
        ink_w = (ADV + 527 - 84 + track) * sc
        gap_px = max(2, round(face*0.07))
        bot = max(2, round(face*0.10))
        block = xh + gap_px + bh
        top_free = face - block - bot
        base = fy0 + max(1, round(top_free*0.55)) + xh
        left = fx0 + (face - ink_w)/2 - 84*sc
        left = round(left*2)/2
        import numpy as np
        acc = np.zeros((W, W), dtype=np.uint8)
        for k, ch in enumerate('nc'):
            ox = left + k*(ADV+track)*sc
            for poly in POLYS[ch]:
                pts = [((ox + x*sc)*SS, (base - y*sc)*SS) for x, y in poly]
                layer = Image.new('L', (W, W), 0)
                ImageDraw.Draw(layer).polygon(pts, fill=255)
                acc ^= np.array(layer)
        tm = Image.fromarray(acc)
        small_txt = None
        bars_bottom = base + gap_px + bh
    # ---- spectrum bars (whole pixels) ----
    total = len(hs)*bw + (len(hs)-1)*bgap
    bx = fx0 + (face - total)//2
    for i, hp in enumerate(hs):
        x = bx + i*(bw+bgap)
        d.rectangle([x*SS, (bars_bottom-hp)*SS, (x+bw)*SS-1, bars_bottom*SS-1], fill=INK+(255,))
    img = img.resize((s, s), Image.BOX)
    tmask = small_txt if small_txt is not None else tm.resize((s, s), Image.BOX)
    img.paste(Image.new('RGBA', (s, s), INK+(255,)), (0, 0), tmask)
    return img

def build(out_ico, preview_dir=None):
    imgs = {s: render(s) for s in SIZES}
    if preview_dir:
        for s, im in imgs.items(): im.save(os.path.join(preview_dir, f'icon{s}.png'))
    write_ico(out_ico, [imgs[s] for s in SIZES])
    return imgs

def write_ico(path, images):
    """classic ICO: 32-bit BGRA DIB + AND mask for < 256 px (what every loader,
    incl. LCL's TIcon, expects), PNG only for the 256 px entry"""
    import struct, io
    blobs = []
    for im in images:
        w, h = im.size
        if w >= 256:
            bio = io.BytesIO(); im.save(bio, 'PNG'); blobs.append(bio.getvalue()); continue
        px = im.convert('RGBA').load()
        hdr = struct.pack('<IiiHHIIiiII', 40, w, h*2, 1, 32, 0, 0, 0, 0, 0, 0)
        xor = bytearray()
        for y in range(h-1, -1, -1):
            for x in range(w):
                r, g, b_, a = px[x, y]; xor += bytes((b_, g, r, a))
        stride = ((w + 31)//32)*4
        andm = bytearray()
        for y in range(h-1, -1, -1):
            row = bytearray(stride)
            for x in range(w):
                if px[x, y][3] == 0: row[x//8] |= 0x80 >> (x % 8)
            andm += row
        blobs.append(hdr + bytes(xor) + bytes(andm))
    out = struct.pack('<HHH', 0, 1, len(images))
    off = 6 + 16*len(images)
    for im, bl in zip(images, blobs):
        w = im.size[0]
        out += struct.pack('<BBBBHHII', w % 256, w % 256, 0, 0, 1, 32, len(bl), off); off += len(bl)
    with open(path, 'wb') as f:
        f.write(out)
        for bl in blobs: f.write(bl)

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'src', 'nc-amp.ico')
    pdir = sys.argv[2] if len(sys.argv) > 2 else None
    build(out, pdir)
    print('wrote', out)
