{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit TagReader;
{ Reads Title/Artist straight from the file: ID3v2 (2.2/2.3/2.4) and ID3v1 (MP3 and
  others), Vorbis comments (FLAC, Ogg Vorbis, Opus), MP4/M4A 'ilst' atoms and APEv2 tags
  (Monkey's Audio, also found on MP3 files).
  Legacy 8-bit tags (very common in Chinese MP3s, GBK) are decoded with the system
  ANSI code page. Durations come from the audio engine (nca_probe). }
{$mode objfpc}{$H+}

interface

uses {$IFDEF MSWINDOWS}Windows, {$ELSE}LConvEncoding, {$ENDIF}SysUtils, Classes, Math, NcAudio;

function ReadTrackInfo(const FileNameUTF8: string; out Title: string; out Duration: Double): Boolean;
function ReadTitle(const FileNameUTF8: string): string;

implementation

function IsValidUTF8(p: PByte; n: Integer): Boolean;
var
  i, k, c: Integer;
begin
  Result := True;
  i := 0;
  while i < n do
  begin
    c := p[i];
    if c < $80 then k := 0
    else if (c and $E0) = $C0 then k := 1
    else if (c and $F0) = $E0 then k := 2
    else if (c and $F8) = $F0 then k := 3
    else Exit(False);
    Inc(i);
    while k > 0 do
    begin
      if (i >= n) or ((p[i] and $C0) <> $80) then Exit(False);
      Inc(i); Dec(k);
    end;
  end;
end;

function AnsiBytesToUTF8(p: PByte; n: Integer): string;
var
  w: UnicodeString;
  m: Integer;
begin
  Result := '';
  while (n > 0) and (p[n-1] in [0, 32]) do Dec(n);
  if n <= 0 then Exit;
  if IsValidUTF8(p, n) then
  begin
    SetString(Result, PAnsiChar(p), n);
    Exit;
  end;
  {$IFDEF MSWINDOWS}
  m := MultiByteToWideChar(CP_ACP, 0, PAnsiChar(p), n, nil, 0);
  SetLength(w, m);
  if m > 0 then MultiByteToWideChar(CP_ACP, 0, PAnsiChar(p), n, PWideChar(w), m);
  Result := UTF8Encode(w);
  {$ELSE}
  { no "ANSI code page" on macOS: legacy tags are GBK in practice (Chinese MP3 collections),
    unless the text only looks sensible as Latin-1 }
  SetString(Result, PAnsiChar(p), n);
  Result := ConvertEncoding(Result, 'cp936', EncodingUTF8);
  w := '';
  m := 0;
  {$ENDIF}
end;

function UTF16ToUTF8(p: PByte; n: Integer; BigEndian: Boolean): string;
var
  w: UnicodeString;
  i, cnt: Integer;
begin
  cnt := n div 2;
  SetLength(w, cnt);
  for i := 0 to cnt - 1 do
    if BigEndian then w[i+1] := WideChar(p[2*i] shl 8 or p[2*i+1])
    else w[i+1] := WideChar(p[2*i+1] shl 8 or p[2*i]);
  while (Length(w) > 0) and (w[Length(w)] = #0) do SetLength(w, Length(w)-1);
  i := Pos(#0, w);
  if i > 0 then SetLength(w, i - 1);
  Result := UTF8Encode(w);
end;

function DecodeID3Text(p: PByte; n: Integer): string;
var
  enc: Byte;
begin
  Result := '';
  if n < 1 then Exit;
  enc := p[0]; Inc(p); Dec(n);
  case enc of
    0: Result := AnsiBytesToUTF8(p, n);
    1: begin
         if (n >= 2) and (p[0] = $FE) and (p[1] = $FF) then Result := UTF16ToUTF8(p+2, n-2, True)
         else if (n >= 2) and (p[0] = $FF) and (p[1] = $FE) then Result := UTF16ToUTF8(p+2, n-2, False)
         else Result := UTF16ToUTF8(p, n, False);
       end;
    2: Result := UTF16ToUTF8(p, n, True);
    3: begin
         while (n > 0) and (p[n-1] = 0) do Dec(n);
         SetString(Result, PAnsiChar(p), n);
       end;
  end;
  Result := Trim(Result);
end;

procedure ParseID3v2(p: PByte; var Title, Artist: string);
var
  ver: Byte;
  total, pos, fsz, hdr: Integer;
  id: string;
  function SyncSafe(q: PByte): Integer;
  begin
    Result := (q[0] and $7F) shl 21 or (q[1] and $7F) shl 14 or (q[2] and $7F) shl 7 or (q[3] and $7F);
  end;
begin
  if (p[0] <> Ord('I')) or (p[1] <> Ord('D')) or (p[2] <> Ord('3')) then Exit;
  ver := p[3];
  total := SyncSafe(p + 6) + 10;
  pos := 10;
  if (ver >= 3) and ((p[5] and $40) <> 0) then  { extended header }
  begin
    if ver = 4 then Inc(pos, SyncSafe(p + 10))
    else Inc(pos, (p[10] shl 24 or p[11] shl 16 or p[12] shl 8 or p[13]) + 4);
  end;
  if ver = 2 then hdr := 6 else hdr := 10;
  while pos + hdr < total do
  begin
    if p[pos] = 0 then Break;
    if ver = 2 then
    begin
      SetString(id, PAnsiChar(p + pos), 3);
      fsz := p[pos+3] shl 16 or p[pos+4] shl 8 or p[pos+5];
    end
    else
    begin
      SetString(id, PAnsiChar(p + pos), 4);
      if ver = 4 then fsz := SyncSafe(p + pos + 4)
      else fsz := p[pos+4] shl 24 or p[pos+5] shl 16 or p[pos+6] shl 8 or p[pos+7];
    end;
    if (fsz <= 0) or (pos + hdr + fsz > total) then Break;
    if (id = 'TIT2') or (id = 'TT2') then Title := DecodeID3Text(p + pos + hdr, fsz)
    else if (id = 'TPE1') or (id = 'TP1') then Artist := DecodeID3Text(p + pos + hdr, fsz);
    Inc(pos, hdr + fsz);
  end;
end;

procedure ParseKeyValueList(p: PAnsiChar; var Title, Artist: string);
var
  s, k, v: string;
  e: Integer;
begin
  if p = nil then Exit;
  while p^ <> #0 do
  begin
    s := StrPas(p);
    Inc(p, Length(s) + 1);
    e := Pos('=', s);
    if e > 0 then
    begin
      k := UpperCase(Copy(s, 1, e - 1));
      v := Trim(Copy(s, e + 1, MaxInt));
      if (k = 'TITLE') and (Title = '') then Title := v
      else if (k = 'ARTIST') and (Artist = '') then Artist := v;
    end;
  end;
end;

{ ---------- file access (UTF-16 paths) ---------- }

function OpenRead(const fn: string): THandleStream;
{$IFDEF MSWINDOWS}
var
  h: THandle;
begin
  Result := nil;
  h := CreateFileW(PWideChar(UTF8Decode(fn)), GENERIC_READ, FILE_SHARE_READ or FILE_SHARE_WRITE,
    nil, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, 0);
  if h <> INVALID_HANDLE_VALUE then Result := THandleStream.Create(h);
end;
{$ELSE}
begin
  Result := nil;
  try
    Result := TFileStream.Create(fn, fmOpenRead or fmShareDenyNone);   { TFileStream is a THandleStream }
  except
    Result := nil;
  end;
end;
{$ENDIF}

procedure CloseRead(var f: THandleStream);
begin
  if f = nil then Exit;
  {$IFDEF MSWINDOWS}
  CloseHandle(f.Handle);
  {$ENDIF}
  FreeAndNil(f);
end;

function ReadBytes(f: TStream; pos: Int64; n: Integer): TBytes;
begin
  SetLength(Result, 0);
  if (n <= 0) or (pos < 0) or (pos >= f.Size) then Exit;
  if pos + n > f.Size then n := f.Size - pos;
  SetLength(Result, n);
  f.Position := pos;
  SetLength(Result, f.Read(Result[0], n));
end;

function LE32(const b: TBytes; i: Integer): Cardinal; inline;
begin
  Result := b[i] or (b[i+1] shl 8) or (b[i+2] shl 16) or (Cardinal(b[i+3]) shl 24);
end;

function BE32(const b: TBytes; i: Integer): Cardinal; inline;
begin
  Result := (Cardinal(b[i]) shl 24) or (b[i+1] shl 16) or (b[i+2] shl 8) or b[i+3];
end;

{ Vorbis comment block (vendor + list) starting at b[i]; KEY=value entries are
  collected into a #0-separated list for ParseKeyValueList }
function VorbisComments(const b: TBytes; i: Integer): AnsiString;
var
  n, cnt, k, len: Cardinal;
  e: AnsiString;
begin
  Result := '';
  if i + 8 > Length(b) then Exit;
  n := LE32(b, i); Inc(i, 4 + Integer(n));
  if i + 4 > Length(b) then Exit;
  cnt := LE32(b, i); Inc(i, 4);
  k := 0;
  while (k < cnt) and (i + 4 <= Length(b)) do
  begin
    len := LE32(b, i); Inc(i, 4);
    if (len > 65536) or (i + Integer(len) > Length(b)) then Break;
    SetString(e, PAnsiChar(@b[i]), len);
    Result := Result + e + #0;
    Inc(i, len); Inc(k);
  end;
end;

{ FLAC metadata blocks -> VORBIS_COMMENT }
function FlacTags(f: TStream; start: Int64): AnsiString;
var
  h, blk: TBytes;
  pos: Int64;
  typ: Byte;
  len: Cardinal;
begin
  Result := '';
  h := ReadBytes(f, start, 4);
  if (Length(h) < 4) or (h[0] <> Ord('f')) or (h[1] <> Ord('L')) or (h[2] <> Ord('a')) or (h[3] <> Ord('C')) then Exit;
  pos := start + 4;
  repeat
    h := ReadBytes(f, pos, 4);
    if Length(h) < 4 then Exit;
    typ := h[0] and $7F;
    len := (h[1] shl 16) or (h[2] shl 8) or h[3];
    if typ = 4 then
    begin
      blk := ReadBytes(f, pos + 4, Integer(len));
      Exit(VorbisComments(blk, 0));
    end;
    pos := pos + 4 + len;
  until (h[0] and $80) <> 0;
end;

{ Ogg: re-assemble the first packets of the first logical stream and parse the
  comment header ("\x03vorbis" or "OpusTags") }
function OggTags(f: TStream): AnsiString;
var
  b, pk: TBytes;
  i, nseg, j, body, plen: Integer;
  serial: Cardinal;
  first: Boolean;
  k: Integer;
begin
  Result := '';
  b := ReadBytes(f, 0, 262144);
  SetLength(pk, 0);
  i := 0; first := True; serial := 0;
  while i + 27 <= Length(b) do
  begin
    if (b[i] <> Ord('O')) or (b[i+1] <> Ord('g')) or (b[i+2] <> Ord('g')) or (b[i+3] <> Ord('S')) then Break;
    nseg := b[i + 26];
    if i + 27 + nseg > Length(b) then Break;
    body := 0;
    for j := 0 to nseg - 1 do Inc(body, b[i + 27 + j]);
    if first then begin serial := LE32(b, i + 14); first := False; end;
    if (LE32(b, i + 14) = serial) and (i + 27 + nseg + body <= Length(b)) then
    begin
      plen := Length(pk);
      SetLength(pk, plen + body);
      Move(b[i + 27 + nseg], pk[plen], body);
    end;
    i := i + 27 + nseg + body;
    if Length(pk) > 200000 then Break;
  end;
  for k := 0 to Length(pk) - 9 do
  begin
    if (pk[k] = 3) and (pk[k+1] = Ord('v')) and (pk[k+2] = Ord('o')) and (pk[k+3] = Ord('r')) and
       (pk[k+4] = Ord('b')) and (pk[k+5] = Ord('i')) and (pk[k+6] = Ord('s')) then
      Exit(VorbisComments(pk, k + 7));
    if (pk[k] = Ord('O')) and (pk[k+1] = Ord('p')) and (pk[k+2] = Ord('u')) and (pk[k+3] = Ord('s')) and
       (pk[k+4] = Ord('T')) and (pk[k+5] = Ord('a')) and (pk[k+6] = Ord('g')) and (pk[k+7] = Ord('s')) then
      Exit(VorbisComments(pk, k + 8));
  end;
end;

{ MP4: moov/udta/meta/ilst -> (c)nam / (c)ART 'data' atoms (UTF-8) }
function Mp4Tags(f: TStream): AnsiString;
  function FindAtom(start, stop: Int64; const name: AnsiString; out bodyStart, bodyEnd: Int64): Boolean;
  var
    h: TBytes;
    pos, sz: Int64;
    t: AnsiString;
  begin
    Result := False;
    pos := start;
    while pos + 8 <= stop do
    begin
      h := ReadBytes(f, pos, 16);
      if Length(h) < 8 then Exit;
      sz := BE32(h, 0);
      SetString(t, PAnsiChar(@h[4]), 4);
      if sz = 1 then
      begin
        if Length(h) < 16 then Exit;
        sz := (Int64(BE32(h, 8)) shl 32) or BE32(h, 12);
        if t = name then begin bodyStart := pos + 16; bodyEnd := pos + sz; Exit(True); end;
      end
      else
      begin
        if sz = 0 then sz := stop - pos;
        if sz < 8 then Exit;
        if t = name then begin bodyStart := pos + 8; bodyEnd := pos + sz; Exit(True); end;
      end;
      pos := pos + sz;
    end;
  end;
  function ItemText(s0, s1: Int64): AnsiString;
  var
    d0, d1: Int64;
    b: TBytes;
  begin
    Result := '';
    if FindAtom(s0, s1, 'data', d0, d1) and (d1 - d0 > 8) and (d1 - d0 < 65536) then
    begin
      b := ReadBytes(f, d0 + 8, Integer(d1 - d0 - 8));       { skip type + locale }
      if Length(b) > 0 then SetString(Result, PAnsiChar(@b[0]), Length(b));
    end;
  end;
var
  m0, m1, u0, u1, t0, t1, i0, i1, a0, a1: Int64;
begin
  Result := '';
  if not FindAtom(0, f.Size, 'moov', m0, m1) then Exit;
  if not FindAtom(m0, m1, 'udta', u0, u1) then Exit;
  if not FindAtom(u0, u1, 'meta', t0, t1) then Exit;
  if not FindAtom(t0 + 4, t1, 'ilst', i0, i1) then Exit;      { meta is a full box }
  if FindAtom(i0, i1, #$A9'nam', a0, a1) then Result := Result + 'TITLE=' + ItemText(a0, a1) + #0;
  if FindAtom(i0, i1, #$A9'ART', a0, a1) then Result := Result + 'ARTIST=' + ItemText(a0, a1) + #0;
end;

{ APEv2 tag (Monkey's Audio; also appended to MP3 and others): the footer sits at the end of the
  file, before an optional ID3v1 tag. Text items -> #0-separated KEY=VALUE list }
function ApeTags(f: TStream): AnsiString;
var
  foot, items: TBytes;
  fpos, tagSize, p, itemsStart: Int64;
  cnt, k, vlen, flags: Cardinal;
  key: AnsiString;
  i, j: Integer;
  v: AnsiString;
begin
  Result := '';
  fpos := f.Size - 32;
  foot := nil;
  for j := 0 to 1 do                                   { footer at the very end, or before ID3v1 }
  begin
    if fpos < 0 then Exit;
    foot := ReadBytes(f, fpos, 32);
    if (Length(foot) = 32) and (CompareByte(foot[0], 'APETAGEX'[1], 8) = 0) then Break;
    foot := nil;
    fpos := f.Size - 128 - 32;
  end;
  if Length(foot) <> 32 then Exit;
  tagSize := LE32(foot, 12);                           { items + footer }
  cnt := LE32(foot, 16);
  if (tagSize < 32) or (tagSize > 4 * 1024 * 1024) or (tagSize - 32 > fpos + 32) then Exit;
  itemsStart := fpos + 32 - tagSize;
  items := ReadBytes(f, itemsStart, Integer(tagSize - 32));
  if Length(items) <> Integer(tagSize - 32) then Exit;
  p := 0;
  k := 0;
  while (k < cnt) and (p + 9 <= Length(items)) do
  begin
    vlen := LE32(items, Integer(p));
    flags := LE32(items, Integer(p) + 4);
    i := Integer(p) + 8;
    key := '';
    while (i < Length(items)) and (items[i] <> 0) do begin key := key + Chr(items[i]); Inc(i); end;
    Inc(i);                                            { the key's #0 }
    if (i > Length(items)) or (Int64(i) + vlen > Length(items)) then Break;
    if (flags and 6) = 0 then                          { text item (not binary / locator) }
    begin
      SetString(v, PAnsiChar(@items[i]), vlen);
      j := Pos(#0, v);                                 { several values: keep the first }
      if j > 0 then v := Copy(v, 1, j - 1);
      Result := Result + key + '=' + v + #0;
    end;
    p := Int64(i) + vlen;
    Inc(k);
  end;
end;

function ReadTitle(const FileNameUTF8: string): string;
var
  f: THandleStream;
  head, tail: TBytes;
  title, artist: string;
  kv: AnsiString;
  id3len: Int64;
  ext: string;
begin
  Result := '';
  title := ''; artist := '';
  f := OpenRead(FileNameUTF8);
  if f = nil then Exit;
  try
    ext := LowerCase(ExtractFileExt(FileNameUTF8));
    id3len := 0;
    head := ReadBytes(f, 0, 10);
    if (Length(head) = 10) and (head[0] = Ord('I')) and (head[1] = Ord('D')) and (head[2] = Ord('3')) then
    begin
      id3len := 10 + ((head[6] and $7F) shl 21 or (head[7] and $7F) shl 14 or (head[8] and $7F) shl 7 or (head[9] and $7F));
      head := ReadBytes(f, 0, Integer(Min(id3len, 4 * 1024 * 1024)));
      if Length(head) = Min(id3len, 4 * 1024 * 1024) then ParseID3v2(@head[0], title, artist);
    end;
    if title = '' then
    begin
      kv := '';
      if (ext = '.flac') then kv := FlacTags(f, id3len)
      else if (ext = '.ogg') or (ext = '.oga') or (ext = '.opus') then kv := OggTags(f)
      else if (ext = '.m4a') or (ext = '.mp4') or (ext = '.m4b') or (ext = '.aac') then kv := Mp4Tags(f);
      if kv = '' then kv := ApeTags(f);          { .ape, and APEv2 tags on MP3 and others }
      if kv <> '' then
      begin
        kv := kv + #0;
        ParseKeyValueList(PAnsiChar(kv), title, artist);
      end;
    end;
    if title = '' then
    begin
      tail := ReadBytes(f, f.Size - 128, 128);       { ID3v1 }
      if (Length(tail) = 128) and (tail[0] = Ord('T')) and (tail[1] = Ord('A')) and (tail[2] = Ord('G')) then
      begin
        title := Trim(AnsiBytesToUTF8(@tail[3], 30));
        if artist = '' then artist := Trim(AnsiBytesToUTF8(@tail[33], 30));
      end;
    end;
  finally
    CloseRead(f);
  end;
  if title = '' then Result := ''
  else if artist <> '' then Result := artist + ' - ' + title
  else Result := title;
end;

function ReadTrackInfo(const FileNameUTF8: string; out Title: string; out Duration: Double): Boolean;
var
  info: TNcaInfo;
begin
  Title := ''; Duration := -1; Result := False;
  if not AudioLoaded then Exit;
  FillChar(info, SizeOf(info), 0);
  if nca_probe_utf8(FileNameUTF8, @info) = 0 then Exit;
  Duration := info.Length;
  Title := ReadTitle(FileNameUTF8);
  Result := True;
end;

end.
