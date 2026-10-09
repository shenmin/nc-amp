{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min

  Binding for the nc-amp audio engine ncaudio.dll (C, see engine/ncaudio.c), which is
  embedded in the exe as RCDATA "NCAUDIO" and extracted to a per-build folder in
  %TEMP% on first use (or loaded from next to the exe if present). }
unit NcAudio;
{$mode objfpc}{$H+}

interface

uses Windows, SysUtils;

type
  TNcaInfo = record
    SampleRate, Channels: Integer;
    Length: Double;          { seconds, <= 0 unknown }
    Bitrate: Integer;        { kbps, average }
    Codec: array[0..15] of AnsiChar;
  end;
  PNcaInfo = ^TNcaInfo;

const
  NCA_STOPPED = 0; NCA_PLAYING = 1; NCA_PAUSED = 2; NCA_ENDED = 3;

var
  nca_init: function: Integer; cdecl;
  nca_uninit: procedure; cdecl;
  nca_open: function(path: PWideChar; info: PNcaInfo): Integer; cdecl;
  nca_close: procedure; cdecl;
  nca_play: procedure; cdecl;
  nca_pause: procedure; cdecl;
  nca_stop: procedure; cdecl;
  nca_state: function: Integer; cdecl;
  nca_get_pos: function: Double; cdecl;
  nca_get_len: function: Double; cdecl;
  nca_seek: function(sec: Double): Integer; cdecl;
  nca_set_volume: procedure(v: Single); cdecl;
  nca_set_pan: procedure(p: Single); cdecl;
  nca_get_fft: function(out512: PSingle): Integer; cdecl;
  nca_probe: function(path: PWideChar; info: PNcaInfo): Integer; cdecl;
  nca_version: function: PAnsiChar; cdecl;
  nca_error: function: PAnsiChar; cdecl;

  AudioLoaded: Boolean = False;     { DLL loaded and functions resolved }
  AudioReady: Boolean = False;      { output device running }
  AudioError: string = '';

function LoadAudio: Boolean;
procedure UnloadAudio;
function AudioVersion: string;

implementation

var
  hLib: HMODULE = 0;

function ExeDirW: UnicodeString;
var
  buf: array[0..MAX_PATH * 2] of WideChar;
  n: DWORD;
begin
  n := GetModuleFileNameW(0, @buf[0], Length(buf));
  SetString(Result, PWideChar(@buf[0]), n);
  while (Result <> '') and (Result[Length(Result)] <> '\') do SetLength(Result, Length(Result) - 1);
end;

function TempDirW: UnicodeString;
var
  buf: array[0..MAX_PATH * 2] of WideChar;
  n: DWORD;
begin
  n := GetTempPathW(Length(buf), @buf[0]);
  SetString(Result, PWideChar(@buf[0]), n);
  if (Result <> '') and (Result[Length(Result)] <> '\') then Result := Result + '\';
end;

function FileExistsW(const fn: UnicodeString): Boolean;
var
  a: DWORD;
begin
  a := GetFileAttributesW(PWideChar(fn));
  Result := (a <> INVALID_FILE_ATTRIBUTES) and ((a and FILE_ATTRIBUTE_DIRECTORY) = 0);
end;

{ FNV-1a over the embedded bytes: a new engine build gets a new folder, so a DLL that
  is still loaded by an old copy is never overwritten }
function Fnv(p: PByte; n: DWORD): DWORD;
var
  i: DWORD;
begin
  Result := 2166136261;
  for i := 0 to n - 1 do Result := (Result xor p[i]) * 16777619;
end;

function ExtractEngine(out Dest: UnicodeString): Boolean;
var
  hRes: HRSRC;
  p: Pointer;
  sz, written: DWORD;
  h: THandle;
  dir: UnicodeString;
begin
  Result := False;
  Dest := '';
  hRes := FindResourceW(HInstance, 'NCAUDIO', PWideChar(RT_RCDATA));
  if hRes = 0 then Exit;
  sz := SizeofResource(HInstance, hRes);
  p := LockResource(LoadResource(HInstance, hRes));
  if p = nil then Exit;
  dir := TempDirW + 'nc-amp_engine_' + UnicodeString(IntToHex(Fnv(p, sz), 8)) + '\';
  CreateDirectoryW(PWideChar(dir), nil);
  Dest := dir + 'ncaudio.dll';
  if FileExistsW(Dest) then Exit(True);
  h := CreateFileW(PWideChar(Dest + '.tmp'), GENERIC_WRITE, 0, nil, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, 0);
  if h = INVALID_HANDLE_VALUE then Exit(FileExistsW(Dest));
  WriteFile(h, p^, sz, written, nil);
  CloseHandle(h);
  if written <> sz then Exit;
  Result := MoveFileW(PWideChar(Dest + '.tmp'), PWideChar(Dest)) or FileExistsW(Dest);
end;

function GP(const n: AnsiString): Pointer;
begin
  Result := GetProcAddress(hLib, PAnsiChar(n));
  if Result = nil then raise Exception.Create('missing ' + n);
end;

function LoadAudio: Boolean;
var
  fn: UnicodeString;
begin
  Result := AudioLoaded;
  if AudioLoaded then Exit;
  fn := ExeDirW + 'ncaudio.dll';               { developer override }
  if not FileExistsW(fn) then
    if not ExtractEngine(fn) then
    begin
      AudioError := 'cannot extract the audio engine';
      Exit(False);
    end;
  hLib := LoadLibraryW(PWideChar(fn));
  if hLib = 0 then
  begin
    AudioError := 'cannot load ncaudio.dll (error ' + IntToStr(GetLastError) + ')';
    Exit(False);
  end;
  try
    Pointer(nca_init) := GP('nca_init');
    Pointer(nca_uninit) := GP('nca_uninit');
    Pointer(nca_open) := GP('nca_open');
    Pointer(nca_close) := GP('nca_close');
    Pointer(nca_play) := GP('nca_play');
    Pointer(nca_pause) := GP('nca_pause');
    Pointer(nca_stop) := GP('nca_stop');
    Pointer(nca_state) := GP('nca_state');
    Pointer(nca_get_pos) := GP('nca_get_pos');
    Pointer(nca_get_len) := GP('nca_get_len');
    Pointer(nca_seek) := GP('nca_seek');
    Pointer(nca_set_volume) := GP('nca_set_volume');
    Pointer(nca_set_pan) := GP('nca_set_pan');
    Pointer(nca_get_fft) := GP('nca_get_fft');
    Pointer(nca_probe) := GP('nca_probe');
    Pointer(nca_version) := GP('nca_version');
    Pointer(nca_error) := GP('nca_error');
  except
    on E: Exception do
    begin
      AudioError := 'audio engine: ' + E.Message;
      FreeLibrary(hLib); hLib := 0;
      Exit(False);
    end;
  end;
  AudioLoaded := True;
  AudioReady := nca_init() <> 0;
  if not AudioReady then AudioError := string(nca_error());
  Result := True;
end;

procedure UnloadAudio;
begin
  if AudioLoaded then nca_uninit();
  AudioLoaded := False;
  AudioReady := False;
  { the DLL stays mapped until exit: the audio thread is already gone }
end;

function AudioVersion: string;
begin
  if AudioLoaded then Result := string(nca_version()) else Result := 'not loaded';
end;

end.
