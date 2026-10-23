{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit M3UFile;
{ Reads and writes M3U / M3U8 playlists (UTF-8) for nc-amp, on Windows and macOS: the playlist
  the user saves and loads, and the player's own playlist.m3u8 that keeps the list over a restart.
  A CUE track is an entry with the audio file, its time range and its title / performer:
    #EXTINF:<seconds>,<performer> - <title>      (what any player shows)
    #EXTVLCOPT:start-time=<s>                    (VLC plays just that part)
    #EXTVLCOPT:stop-time=<s>
    #NCAMP-CUE:start=<s>;end=<s>;performer=<..>;title=<..>   (exact data for nc-amp; ';' '%' and
                                                              control characters are %XX escaped)
    <path of the audio file>
  Paths are written relative to the playlist's folder when the file is below it, else absolute.
  Reading accepts UTF-8 with or without BOM (anything else is decoded like a CUE sheet, GBK too),
  CRLF / LF, relative and absolute paths, '/' and '\' separators, plain lists without #EXTM3U. }
{$mode objfpc}{$H+}

interface

uses SysUtils, Classes, CueSheet;

type
  TPlEntry = record
    Path: string;           { UTF-8, absolute after reading }
    Title: string;          { shown title: the CUE track's TITLE; '' = read the tags }
    Performer: string;
    IsCue: Boolean;
    Start, Stop: Double;    { CUE track range in the file (Stop 0 = to the end) }
    Duration: Double;       { seconds, -1 unknown (written to #EXTINF) }
  end;
  TPlEntries = array of TPlEntry;

{ KeepMissing: entries whose file does not exist are kept (the player's own list) or skipped }
function ReadM3U(const FileName: string; KeepMissing: Boolean; out Entries: TPlEntries; out Missing: Integer): Boolean;
{ Relative: paths below the playlist's folder are written relative to it }
function WriteM3U(const FileName: string; const Entries: TPlEntries; Relative: Boolean): Boolean;

implementation

uses Math{$IFDEF MSWINDOWS}, Windows{$ELSE}, BaseUnix{$ENDIF};

function DotFmt: TFormatSettings;
begin
  Result := DefaultFormatSettings;
  Result.DecimalSeparator := '.';
end;

function PctEnc(const s: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(s) do
    if (s[i] in [#0..#31, '%', ';']) then Result := Result + '%' + IntToHex(Ord(s[i]), 2)
    else Result := Result + s[i];
end;

function PctDec(const s: string): string;
var
  i, v: Integer;
begin
  Result := '';
  i := 1;
  while i <= Length(s) do
  begin
    if (s[i] = '%') and (i + 2 <= Length(s)) and TryStrToInt('$' + Copy(s, i + 1, 2), v) then
    begin
      Result := Result + Chr(v);
      Inc(i, 3);
    end
    else
    begin
      Result := Result + s[i];
      Inc(i);
    end;
  end;
end;

function Pos0(v: Double): Double;
begin
  if v > 0 then Result := v else Result := 0;
end;

function SecStr(v: Double): string;
begin
  Result := FormatFloat('0.######', v, DotFmt);
end;

function IsAbsPath(const s: string): Boolean;
begin
  Result := (s <> '') and ((s[1] = '/') or (s[1] = '\') or ((Length(s) > 1) and (s[2] = ':')));
end;

function ReadM3U(const FileName: string; KeepMissing: Boolean; out Entries: TPlEntries; out Missing: Integer): Boolean;
var
  txt, line, base, p, key, val, cmd: string;
  L, parts: TStringList;
  i, j, n, eq: Integer;
  cur: TPlEntry;
  hasCue: Boolean;
  extTitle: string;
  v: Double;

  procedure Reset;
  begin
    cur.Path := ''; cur.Title := ''; cur.Performer := ''; cur.IsCue := False;
    cur.Start := 0; cur.Stop := 0; cur.Duration := -1;
    hasCue := False; extTitle := '';
  end;

  function Resolve(const s: string): string;
  var
    t: string;
  begin
    t := s;
    {$IFDEF MSWINDOWS}
    t := StringReplace(t, '/', '\', [rfReplaceAll]);
    {$ELSE}
    if not FileExists(t) and not FileExists(base + t) then t := StringReplace(t, '\', '/', [rfReplaceAll]);
    {$ENDIF}
    if not IsAbsPath(t) then t := base + t;
    Result := ExpandFileName(t);
  end;

begin
  SetLength(Entries, 0);
  Missing := 0;
  if not LoadTextFile(FileName, txt) then Exit(False);
  Result := True;
  base := IncludeTrailingPathDelimiter(ExtractFilePath(ExpandFileName(FileName)));
  L := TStringList.Create;
  parts := TStringList.Create;
  try
    L.Text := StringReplace(StringReplace(txt, #13#10, #10, [rfReplaceAll]), #13, #10, [rfReplaceAll]);
    n := 0;
    Reset;
    for i := 0 to L.Count - 1 do
    begin
      line := Trim(L[i]);
      if line = '' then Continue;
      if line[1] = '#' then
      begin
        if Copy(UpperCase(line), 1, 8) = '#EXTINF:' then
        begin
          p := Copy(line, 9, MaxInt);
          j := Pos(',', p);
          if j > 0 then
          begin
            if TryStrToFloat(Trim(Copy(p, 1, j - 1)), v, DotFmt) and (v > 0) then cur.Duration := v;
            extTitle := Trim(Copy(p, j + 1, MaxInt));
          end;
        end
        else if Copy(UpperCase(line), 1, 11) = '#NCAMP-CUE:' then
        begin
          p := Copy(line, 12, MaxInt);
          parts.Clear;
          parts.Delimiter := ';'; parts.StrictDelimiter := True; parts.DelimitedText := p;
          for j := 0 to parts.Count - 1 do
          begin
            eq := Pos('=', parts[j]);
            if eq < 2 then Continue;
            key := LowerCase(Copy(parts[j], 1, eq - 1));
            val := Copy(parts[j], eq + 1, MaxInt);
            if key = 'start' then begin if TryStrToFloat(val, v, DotFmt) then cur.Start := Pos0(v); hasCue := True; end
            else if key = 'end' then begin if TryStrToFloat(val, v, DotFmt) then cur.Stop := Pos0(v); end
            else if key = 'performer' then cur.Performer := PctDec(val)
            else if key = 'title' then cur.Title := PctDec(val);
          end;
        end;
        Continue;
      end;
      { a path }
      cmd := line;
      if Copy(LowerCase(cmd), 1, 7) = 'file://' then Continue;
      cur.Path := Resolve(cmd);
      cur.IsCue := hasCue;
      if not cur.IsCue then cur.Title := '';
      if FileExists(cur.Path) or KeepMissing then
      begin
        SetLength(Entries, n + 1);
        Entries[n] := cur;
        Inc(n);
      end
      else Inc(Missing);
      Reset;
    end;
  finally
    L.Free;
    parts.Free;
  end;
end;

function RelPath(const Path, BaseDir: string): string;
var
  b: string;
begin
  Result := Path;
  b := IncludeTrailingPathDelimiter(BaseDir);
  {$IFDEF MSWINDOWS}
  if (Length(Path) > Length(b)) and SameText(Copy(Path, 1, Length(b)), b) then
  {$ELSE}
  if (Length(Path) > Length(b)) and (Copy(Path, 1, Length(b)) = b) then
  {$ENDIF}
    Result := StringReplace(Copy(Path, Length(b) + 1, MaxInt), '\', '/', [rfReplaceAll]);
end;

function WriteM3U(const FileName: string; const Entries: TPlEntries; Relative: Boolean): Boolean;
var
  L: TStringList;
  tmp, base, shown: string;
  i: Integer;
  e: TPlEntry;
  s: string;
begin
  Result := False;
  base := ExtractFilePath(ExpandFileName(FileName));
  L := TStringList.Create;
  try
    L.Add('#EXTM3U');
    for i := 0 to High(Entries) do
    begin
      e := Entries[i];
      if e.IsCue then
      begin
        if e.Performer <> '' then shown := e.Performer + ' - ' + e.Title else shown := e.Title;
      end
      else shown := e.Title;
      shown := StringReplace(StringReplace(shown, #13, ' ', [rfReplaceAll]), #10, ' ', [rfReplaceAll]);
      if (shown <> '') or (e.Duration > 0) then
        L.Add('#EXTINF:' + IntToStr(Round(Pos0(e.Duration)) + Ord(e.Duration <= 0) * -1) + ',' + shown);
      if e.IsCue then
      begin
        L.Add('#EXTVLCOPT:start-time=' + SecStr(e.Start));
        if e.Stop > 0 then L.Add('#EXTVLCOPT:stop-time=' + SecStr(e.Stop));
        s := '#NCAMP-CUE:start=' + SecStr(e.Start);
        if e.Stop > 0 then s := s + ';end=' + SecStr(e.Stop);
        s := s + ';performer=' + PctEnc(e.Performer) + ';title=' + PctEnc(e.Title);
        L.Add(s);
      end;
      if Relative then L.Add(RelPath(e.Path, base)) else L.Add(e.Path);
    end;
    tmp := FileName + '.tmp';
    try
      L.WriteBOM := False;                 { UTF-8 without BOM; the line ends are CRLF on Windows, LF on macOS }
      L.SaveToFile(tmp);
      {$IFDEF MSWINDOWS}
      Result := MoveFileExW(PWideChar(UTF8Decode(tmp)), PWideChar(UTF8Decode(FileName)),
        MOVEFILE_REPLACE_EXISTING or $8 { MOVEFILE_WRITE_THROUGH });
      {$ELSE}
      Result := fpRename(tmp, FileName) = 0;   { rename(2) replaces atomically }
      {$ENDIF}
      if not Result then SysUtils.DeleteFile(tmp);
    except
      Result := False;
    end;
  finally
    L.Free;
  end;
end;

end.
