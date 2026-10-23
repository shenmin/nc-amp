#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 Shen Min
# make-cue-test.sh <dir>: test material for CUE support - a 40.5 s "album" of five sine tracks
# (220 / 330 / 440 / 550 / 660 Hz; 8, 7.5, 9, 6, 10 s) as WAV, FLAC and MP3 (needs ffmpeg; add album.ape
# made with Monkey's Audio's `mac album.wav album.ape -c2000` for the APE sheet), plus sheets for them:
# UTF-8 (with BOM, CRLF), GBK (LF) and unquoted GBK, one that names a WAV that is really a FLAC, one in
# a sub-folder with a relative path, and one with two FILE entries (part1.flac / part2.ape).
# Check with: tests/cue/cuetest <dir>/flac_utf8.cue tone-test  (see build-cuetest.sh)
set -e
D=${1:?usage: make-cue-test.sh dir}
mkdir -p "$D/sub" && cd "$D"
mk() { ffmpeg -v error -y -f lavfi -i "sine=frequency=$1:duration=$2:sample_rate=44100" -ac 2 "$3"; }
mk 220 8 t1.wav; mk 330 7.5 t2.wav; mk 440 9 t3.wav; mk 550 6 t4.wav; mk 660 10 t5.wav
printf "file 't%s.wav'\n" 1 2 3 4 5 > list.txt
ffmpeg -v error -y -f concat -safe 0 -i list.txt -c copy album.wav
ffmpeg -v error -y -i album.wav album.flac
ffmpeg -v error -y -i album.wav -b:a 128k album.mp3
printf "file 't1.wav'\nfile 't2.wav'\n" > p1.list; printf "file 't3.wav'\nfile 't4.wav'\nfile 't5.wav'\n" > p2.list
ffmpeg -v error -y -f concat -safe 0 -i p1.list -c copy p1.wav; ffmpeg -v error -y -f concat -safe 0 -i p2.list -c copy p2.wav
ffmpeg -v error -y -i p1.wav part1.flac
command -v mac >/dev/null && mac p2.wav part2.ape -c3000 >/dev/null || echo "(no 'mac' encoder: part2.ape / album.ape not made)"
python3 - <<'PY'
tracks = [("夜曲", "周杰伦", "00:00:00", None), ("七里香", "周杰伦", "00:08:00", "00:07:50"),
          ("Blue Sky", "Test Artist", "00:15:37", "00:15:30"), ("稻香", "周杰伦", "00:24:37", None),
          ("晴天", "周杰伦", "00:30:37", "00:30:20")]
def make(fname, ftype, quoted=True, nl="\r\n"):
    L = ['REM GENRE Pop', 'REM COMMENT "nc-amp test"', 'PERFORMER "周杰伦"', 'TITLE "测试专辑 Album"']
    L.append('FILE "%s" %s' % (fname, ftype) if quoted else 'FILE %s %s' % (fname, ftype))
    for i, (t, p, s, pre) in enumerate(tracks, 1):
        L.append('  TRACK %02d AUDIO' % i)
        L += ['    TITLE "%s"' % t, '    PERFORMER "%s"' % p] if quoted else ['    TITLE %s' % t, '    PERFORMER %s' % p]
        if pre: L.append('    INDEX 00 %s' % pre)
        L.append('    INDEX 01 %s' % s)
    return nl.join(L) + nl
def w(name, txt, enc): open(name, 'wb').write(txt.encode(enc))
w('flac_utf8.cue', make('album.flac', 'FLAC'), 'utf-8')
w('ape_utf8bom.cue', make('album.ape', 'APE'), 'utf-8-sig')
w('wav_gbk.cue', make('album.wav', 'WAVE', nl="\n"), 'gbk')
w('mp3_gbk_unq.cue', make('album.mp3', 'MP3', quoted=False), 'gbk')
w('sub/rel.cue', make('../album.flac', 'FLAC'), 'utf-8')
open('multi.cue', 'w').write('''PERFORMER "Multi Artist"
TITLE "Two files"
FILE "part1.flac" WAVE
  TRACK 01 AUDIO
    TITLE "One"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Two"
    INDEX 00 00:07:00
    INDEX 01 00:08:00
FILE "part2.ape" WAVE
  TRACK 03 AUDIO
    TITLE "Three"
    PERFORMER "Other"
    INDEX 01 00:00:00
  TRACK 04 AUDIO
    TITLE "Four"
    INDEX 01 00:09:00
  TRACK 05 AUDIO
    INDEX 01 00:15:00
''')
PY
echo "made the test material in $D"
