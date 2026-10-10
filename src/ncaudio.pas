{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min

  Binding for the nc-amp audio engine (C, see engine/ncaudio.c). Since 2.0.0 the engine
  is linked statically into nc-amp.exe: scripts/build-engine.sh compiles it with MinGW-w64
  (engine + opusfile; miniaudio and stb_vorbis are included by ncaudio.c) and puts these
  objects plus exactly the members of the static libraries they need (libopus, libogg, the
  static part of MinGW's msvcrt library, mingwex, libgcc) into engine/obj, listed in
  engine/objs.inc. The only imports left are kernel32 / ole32 / msvcrt, from the MinGW
  import libraries in engine/lib. No MinGW start-up code runs (see engine/nccrt.c); no DLL
  is written or loaded. }
unit NcAudio;
{$mode objfpc}{$H+}

{ the engine objects (generated list), then the import libraries for what they use from
  kernel32.dll / ole32.dll / msvcrt.dll }
{$I engine/objs.inc}
{$LINKLIB libmsvcrt.a}
{$LINKLIB libole32.a}
{$LINKLIB libkernel32.a}

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

function nca_init: Integer; cdecl; external name 'nca_init';
procedure nca_uninit; cdecl; external name 'nca_uninit';
function nca_open(path: PWideChar; info: PNcaInfo): Integer; cdecl; external name 'nca_open';
procedure nca_close; cdecl; external name 'nca_close';
procedure nca_play; cdecl; external name 'nca_play';
procedure nca_pause; cdecl; external name 'nca_pause';
procedure nca_stop; cdecl; external name 'nca_stop';
function nca_state: Integer; cdecl; external name 'nca_state';
function nca_get_pos: Double; cdecl; external name 'nca_get_pos';
function nca_get_len: Double; cdecl; external name 'nca_get_len';
function nca_seek(sec: Double): Integer; cdecl; external name 'nca_seek';
procedure nca_set_volume(v: Single); cdecl; external name 'nca_set_volume';
procedure nca_set_pan(p: Single); cdecl; external name 'nca_set_pan';
function nca_get_fft(out512: PSingle): Integer; cdecl; external name 'nca_get_fft';
function nca_probe(path: PWideChar; info: PNcaInfo): Integer; cdecl; external name 'nca_probe';
function nca_version: PAnsiChar; cdecl; external name 'nca_version';
function nca_error: PAnsiChar; cdecl; external name 'nca_error';
{ diagnostics (1.7.2+) }
function nca_take_log(buf: PAnsiChar; cap: Integer): Integer; cdecl; external name 'nca_take_log';
function nca_take_peak(callbacks, frames: PInteger): Single; cdecl; external name 'nca_take_peak';
procedure nca_poll; cdecl; external name 'nca_poll';
{ 1.7.8: 1 = playback was paused because the output device changed; reason in buf }
function nca_take_autopause(buf: PAnsiChar; cap: Integer): Integer; cdecl; external name 'nca_take_autopause';

var
  AudioLoaded: Boolean = False;     { engine initialised (nca_init called) }
  AudioReady: Boolean = False;      { output device running }
  AudioError: string = '';

function LoadAudio: Boolean;
procedure UnloadAudio;
function AudioVersion: string;
{ engine log lines since the last call (empty string if none) }
function AudioTakeLog: string;

implementation

function LoadAudio: Boolean;
begin
  Result := True;
  if AudioLoaded then Exit;
  AudioLoaded := True;
  AudioReady := nca_init() <> 0;
  if not AudioReady then AudioError := string(nca_error());
end;

procedure UnloadAudio;
begin
  if AudioLoaded then nca_uninit();
  AudioLoaded := False;
  AudioReady := False;
end;

function AudioTakeLog: string;
var
  buf: array[0..16383] of AnsiChar;
  n: Integer;
begin
  Result := '';
  if not AudioLoaded then Exit;
  n := nca_take_log(@buf[0], SizeOf(buf));
  if n > 0 then SetString(Result, PAnsiChar(@buf[0]), n);
end;

function AudioVersion: string;
begin
  if AudioLoaded then Result := string(nca_version()) else Result := 'not loaded';
end;

end.
