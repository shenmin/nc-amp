{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit CueSheet;
{ CUE sheet parser (shared by Windows and macOS).
  A .cue file becomes a list of tracks: the audio file, TITLE / PERFORMER (track level, else the
  album's) and the range [INDEX 01 of the track, INDEX 01 of the next track of the same FILE)
  in seconds. INDEX 00 (pre-gap), REM and unknown commands are ignored; several FILE entries,
  quoted and unquoted strings, CRLF / LF / CR line ends are handled. The text may be UTF-8 (with
  or without BOM), UTF-16 (BOM) or a legacy GBK / GB18030 file (Chinese CUE sheets): anything
  that is not valid UTF-8 is read as GB18030 (Windows: the system converter, macOS: Core
  Foundation, otherwise GBK from LConvEncoding). Also provides DecodeTextBytes for the M3U reader. }
{$mode objfpc}{$H+}

interface

uses SysUtils, Classes;

type
  TCueTrack = record
    Audio: string;        { the audio file (UTF-8 path, exists) }
    Title: string;        { track TITLE, else the album TITLE, else the audio file's name }
    Performer: string;    { track PERFORMER, else the album PERFORMER, else '' }
    Number: Integer;
    Start: Double;        { seconds into Audio (INDEX 01) }
    Stop: Double;         { seconds; 0 = to the end of the audio file }
  end;
  TCueTracks = array of TCueTrack;

{ text bytes (file content) -> UTF-8 }
function DecodeTextBytes(const Raw: RawByteString): string;
function LoadTextFile(const FileName: string; out Text: string): Boolean;
{ parses the sheet; Tracks is empty if nothing is playable. Skipped = tracks dropped because their
  audio file does not exist. Result: the file could be read. }
function ParseCueFile(const FileName: string; out Tracks: TCueTracks; out Skipped: Integer): Boolean;
function ParseCueText(const Text, CueDir: string; out Tracks: TCueTracks; out Skipped: Integer): Boolean;
{ mm:ss:ff (75 frames per second) -> seconds; -1 if malformed }
function CueTimeToSec(const S: string): Double;
{ find the audio file a FILE line names: as written (relative to the sheet's folder), with the
  path separators fixed, or the same name with another audio extension }
function ResolveCueAudio(const CueDir, Name: string): string;

implementation

{$IFDEF MSWINDOWS}
uses Windows;
{$ELSE}
{$IFDEF DARWIN}
uses MacOSAll, LConvEncoding;
{$ELSE}
uses LConvEncoding;
{$ENDIF}
{$ENDIF}

function IsValidUTF8Bytes(p: PByte; n: Integer): Boolean;
var
  i, k, c: Integer;
begin
  Result := True;
  i := 0;
  while i < n do
  begin
    c := p[i];
    if c < $80 then k := 0
    else if (c and $E0) = $C0 then begin if c < $C2 then Exit(False); k := 1; end
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

function Utf16ToUtf8(const Raw: RawByteString; From: Integer; BigEndian: Boolean): string;
var
  w: UnicodeString;
  i, n: Integer;
  lo, hi: Byte;
begin
  n := (Length(Raw) - From + 1) div 2;
  SetLength(w, n);
  for i := 0 to n - 1 do
  begin
    lo := Byte(Raw[From + i * 2]); hi := Byte(Raw[From + i * 2 + 1]);
    if BigEndian then w[i + 1] := System.WideChar(Word((Word(lo) shl 8) or hi))
    else w[i + 1] := System.WideChar(Word((Word(hi) shl 8) or lo));
  end;
  Result := UTF8Encode(w);
end;

{ legacy Chinese text: GB18030 (a superset of GBK) }
function LegacyToUtf8(const Raw: RawByteString): string;
{$IFDEF MSWINDOWS}
var
  w: UnicodeString;
  m: Integer;
begin
  Result := '';
  if Raw = '' then Exit;
  m := MultiByteToWideChar(54936, 0, PAnsiChar(Raw), Length(Raw), nil, 0);
  if m > 0 then
  begin
    SetLength(w, m);
    MultiByteToWideChar(54936, 0, PAnsiChar(Raw), Length(Raw), PWideChar(w), m);
    Exit(UTF8Encode(w));
  end;
  m := MultiByteToWideChar(936, 0, PAnsiChar(Raw), Length(Raw), nil, 0);
  if m <= 0 then m := MultiByteToWideChar(CP_ACP, 0, PAnsiChar(Raw), Length(Raw), nil, 0);
  SetLength(w, m);
  if m > 0 then MultiByteToWideChar(936, 0, PAnsiChar(Raw), Length(Raw), PWideChar(w), m);
  Result := UTF8Encode(w);
end;
{$ELSE}
{$IFDEF DARWIN}
var
  cfs: CFStringRef;
  n: CFIndex;
  buf: array of AnsiChar;
begin
  Result := '';
  if Raw = '' then Exit;
  cfs := CFStringCreateWithBytes(nil, PByte(PAnsiChar(Raw)), Length(Raw), $0632 {kCFStringEncodingGB_18030_2000}, False);
  if cfs <> nil then
  begin
    n := CFStringGetMaximumSizeForEncoding(CFStringGetLength(cfs), kCFStringEncodingUTF8) + 1;
    SetLength(buf, n);
    if CFStringGetCString(cfs, @buf[0], n, kCFStringEncodingUTF8) then Result := PAnsiChar(@buf[0]);
    CFRelease(cfs);
    if Result <> '' then Exit;
  end;
  Result := ConvertEncoding(Raw, 'cp936', EncodingUTF8);
end;
{$ELSE}
begin
  Result := ConvertEncoding(Raw, 'cp936', EncodingUTF8);
end;
{$ENDIF}
{$ENDIF}

function DecodeTextBytes(const Raw: RawByteString): string;
begin
  Result := '';
  if Raw = '' then Exit;
  if (Length(Raw) >= 3) and (Raw[1] = #$EF) and (Raw[2] = #$BB) and (Raw[3] = #$BF) then
    Exit(Copy(Raw, 4, MaxInt));
  if (Length(Raw) >= 2) and (Raw[1] = #$FF) and (Raw[2] = #$FE) then Exit(Utf16ToUtf8(Raw, 3, False));
  if (Length(Raw) >= 2) and (Raw[1] = #$FE) and (Raw[2] = #$FF) then Exit(Utf16ToUtf8(Raw, 3, True));
  if IsValidUTF8Bytes(PByte(PAnsiChar(Raw)), Length(Raw)) then Exit(Raw);
  Result := LegacyToUtf8(Raw);
end;

function LoadTextFile(const FileName: string; out Text: string): Boolean;
var
  fs: TFileStream;
  raw: RawByteString;
begin
  Text := '';
  Result := False;
  try
    fs := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
    try
      if fs.Size > 16 * 1024 * 1024 then Exit;
      SetLength(raw, fs.Size);
      if fs.Size > 0 then fs.ReadBuffer(raw[1], fs.Size);
    finally
      fs.Free;
    end;
    Text := DecodeTextBytes(raw);
    Result := True;
  except
    Result := False;
  end;
end;

function CueTimeToSec(const S: string): Double;
var
  p: TStringArray;
  m, sec, f: Integer;
begin
  Result := -1;
  p := Trim(S).Split([':']);
  if Length(p) = 3 then
  begin
    if TryStrToInt(Trim(p[0]), m) and TryStrToInt(Trim(p[1]), sec) and TryStrToInt(Trim(p[2]), f) and
      (m >= 0) and (sec >= 0) and (f >= 0) then
      Result := m * 60.0 + sec + f / 75.0;
  end
  else if Length(p) = 2 then
    if TryStrToInt(Trim(p[0]), m) and TryStrToInt(Trim(p[1]), sec) and (m >= 0) and (sec >= 0) then
      Result := m * 60.0 + sec;
end;

function FixSeparators(const S: string): string;
var
  i: Integer;
begin
  Result := S;
  for i := 1 to Length(Result) do
    if (Result[i] = '\') or (Result[i] = '/') then Result[i] := PathDelim;
end;

function ResolveCueAudio(const CueDir, Name: string): string;
const
  EXTS: array[0..13] of string = ('.flac', '.ape', '.wav', '.wv', '.mp3', '.m4a', '.ogg', '.opus',
    '.tta', '.aiff', '.aif', '.alac', '.mp2', '.aac');
var
  n, base: string;
  i: Integer;

  function Abs_(const s: string): Boolean;
  begin
    Result := (s <> '') and ((s[1] = PathDelim) or ((Length(s) > 1) and (s[2] = ':')));
  end;

  function Full(const s: string): string;
  begin
    if Abs_(s) then Result := s else Result := IncludeTrailingPathDelimiter(CueDir) + s;
  end;

begin
  Result := '';
  n := Trim(Name);
  if n = '' then Exit;
  {$IFDEF MSWINDOWS}
  n := FixSeparators(n);
  {$ELSE}
  { a '\' is a separator in sheets written on Windows - unless the name really has one }
  if not FileExists(Full(n)) then n := FixSeparators(n);
  {$ENDIF}
  if FileExists(Full(n)) then Exit(ExpandFileName(Full(n)));
  { the sheet names the original WAV, the file is the FLAC / APE it was compressed to }
  base := ChangeFileExt(n, '');
  for i := 0 to High(EXTS) do
    if FileExists(Full(base + EXTS[i])) then Exit(ExpandFileName(Full(base + EXTS[i])));
  { same name in the sheet's folder, whatever the sheet's path }
  base := ExtractFileName(n);
  if (base <> n) and FileExists(IncludeTrailingPathDelimiter(CueDir) + base) then
    Exit(ExpandFileName(IncludeTrailingPathDelimiter(CueDir) + base));
  base := ChangeFileExt(base, '');
  for i := 0 to High(EXTS) do
    if FileExists(IncludeTrailingPathDelimiter(CueDir) + base + EXTS[i]) then
      Exit(ExpandFileName(IncludeTrailingPathDelimiter(CueDir) + base + EXTS[i]));
end;

{ first token of a line (upper case) and the rest }
procedure SplitCmd(const Line: string; out Cmd, Rest: string);
var
  i: Integer;
begin
  i := 1;
  while (i <= Length(Line)) and not (Line[i] in [' ', #9]) do Inc(i);
  Cmd := UpperCase(Copy(Line, 1, i - 1));
  Rest := Trim(Copy(Line, i, MaxInt));
end;

{ "quoted string" (anything after the closing quote is dropped), or the whole unquoted rest }
function CueString(const S: string): string;
var
  q: Integer;
begin
  Result := Trim(S);
  if (Result <> '') and (Result[1] = '"') then
  begin
    q := Pos('"', Copy(Result, 2, MaxInt));
    if q > 0 then Result := Copy(Result, 2, q - 1) else Result := Copy(Result, 2, MaxInt);
  end;
end;

{ FILE "name with spaces.wav" WAVE  /  FILE name.wav WAVE }
function CueFileName(const S: string): string;
var
  t: string;
  i: Integer;
begin
  t := Trim(S);
  if (t <> '') and (t[1] = '"') then Exit(CueString(t));
  i := LastDelimiter(' ' + #9, t);
  if (i > 1) and (Pos('.', Copy(t, i + 1, MaxInt)) = 0) then Result := Trim(Copy(t, 1, i - 1))
  else Result := t;
end;

function ParseCueText(const Text, CueDir: string; out Tracks: TCueTracks; out Skipped: Integer): Boolean;
type
  TRawTrack = record
    FileIdx, Number: Integer;
    Title, Performer: string;
    Start: Double;
    HasStart, Audio: Boolean;
  end;
var
  lines: TStringList;
  raw: array of TRawTrack;
  files: array of string;      { resolved audio path ('' = missing) }
  albumTitle, albumPerf, cmd, rest, line, a, b: string;
  nRaw, curFile, i, j, n, num: Integer;
  inTrack: Boolean;
  t: Double;
begin
  Result := True;
  SetLength(Tracks, 0);
  SetLength(raw, 0); SetLength(files, 0);
  Skipped := 0;
  albumTitle := ''; albumPerf := '';
  nRaw := 0; curFile := -1; inTrack := False;
  lines := TStringList.Create;
  try
    lines.Text := StringReplace(StringReplace(Text, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    for i := 0 to lines.Count - 1 do
    begin
      line := Trim(lines[i]);
      if line = '' then Continue;
      SplitCmd(line, cmd, rest);
      if cmd = 'FILE' then
      begin
        SetLength(files, Length(files) + 1);
        curFile := High(files);
        files[curFile] := ResolveCueAudio(CueDir, CueFileName(rest));
        inTrack := False;
      end
      else if cmd = 'TRACK' then
      begin
        SplitCmd(rest, a, b);
        if not TryStrToInt(a, num) then num := nRaw + 1;
        SetLength(raw, nRaw + 1);
        raw[nRaw].FileIdx := curFile; raw[nRaw].Number := num;
        raw[nRaw].Title := ''; raw[nRaw].Performer := '';
        raw[nRaw].Start := 0; raw[nRaw].HasStart := False;
        raw[nRaw].Audio := Pos('AUDIO', UpperCase(b)) = 1;
        Inc(nRaw);
        inTrack := True;
      end
      else if cmd = 'TITLE' then
      begin
        if inTrack then raw[nRaw - 1].Title := CueString(rest) else albumTitle := CueString(rest);
      end
      else if cmd = 'PERFORMER' then
      begin
        if inTrack then raw[nRaw - 1].Performer := CueString(rest) else albumPerf := CueString(rest);
      end
      else if (cmd = 'INDEX') and inTrack then
      begin
        SplitCmd(rest, a, b);
        { INDEX 01 is the start; INDEX 00 (pre-gap) and further sub-indices are ignored }
        if TryStrToInt(a, num) and (num = 1) then
        begin
          t := CueTimeToSec(b);
          if t >= 0 then begin raw[nRaw - 1].Start := t; raw[nRaw - 1].HasStart := True; end;
        end;
      end;
      { REM, CATALOG, ISRC, FLAGS, PREGAP, POSTGAP, SONGWRITER, CDTEXTFILE ...: ignored }
    end;
  finally
    lines.Free;
  end;
  n := 0;
  for i := 0 to nRaw - 1 do
  begin
    if not raw[i].Audio or not raw[i].HasStart or (raw[i].FileIdx < 0) then Continue;
    if files[raw[i].FileIdx] = '' then begin Inc(Skipped); Continue; end;
    SetLength(Tracks, n + 1);
    Tracks[n].Audio := files[raw[i].FileIdx];
    Tracks[n].Number := raw[i].Number;
    Tracks[n].Start := raw[i].Start;
    Tracks[n].Stop := 0;
    { ends where the next track of the same FILE starts }
    for j := i + 1 to nRaw - 1 do
      if (raw[j].FileIdx = raw[i].FileIdx) and raw[j].HasStart then
      begin
        if raw[j].Start > raw[i].Start then Tracks[n].Stop := raw[j].Start;
        Break;
      end
      else if raw[j].FileIdx <> raw[i].FileIdx then Break;
    Tracks[n].Title := raw[i].Title;
    if Tracks[n].Title = '' then Tracks[n].Title := albumTitle;
    if Tracks[n].Title = '' then Tracks[n].Title := ChangeFileExt(ExtractFileName(Tracks[n].Audio), '');
    Tracks[n].Performer := raw[i].Performer;
    if Tracks[n].Performer = '' then Tracks[n].Performer := albumPerf;
    Inc(n);
  end;
end;

function ParseCueFile(const FileName: string; out Tracks: TCueTracks; out Skipped: Integer): Boolean;
var
  txt: string;
begin
  SetLength(Tracks, 0);
  Skipped := 0;
  if not LoadTextFile(FileName, txt) then Exit(False);
  Result := ParseCueText(txt, ExtractFilePath(ExpandFileName(FileName)), Tracks, Skipped);
end;

end.
