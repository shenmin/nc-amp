{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min

  Console test of the Windows engine as linked into nc-amp.exe (run it under Wine or on Windows):
    wintest file.ape [seek-seconds]
  probes the file (duration, bitrate, title), opens it, seeks, plays for two seconds and prints
  the position. Build: tests/ape/build-wintest.sh }
program wintest;
{$mode objfpc}{$H+}
uses SysUtils, NcAudio, TagReader;

var
  info: TNcaInfo;
  title: string;
  dur, pos0, pos1: Double;
  i: Integer;
begin
  if ParamCount < 1 then begin WriteLn('usage: wintest file [seek-seconds]'); Halt(2); end;
  LoadAudio;
  WriteLn('engine: ', AudioVersion, '; device ready: ', AudioReady);
  if not ReadTrackInfo(ParamStr(1), title, dur) then begin WriteLn('FAIL probe'); Halt(1); end;
  FillChar(info, SizeOf(info), 0);
  nca_probe_utf8(ParamStr(1), @info);
  WriteLn(Format('probe: %.3f s, %d Hz, %d ch, %d kbps, codec %s, title "%s"', [dur, info.SampleRate, info.Channels, info.Bitrate, PAnsiChar(@info.Codec[0]), title]));
  FillChar(info, SizeOf(info), 0);
  if nca_open_utf8(ParamStr(1), @info) = 0 then begin WriteLn('FAIL open: ', string(nca_error())); Halt(1); end;
  WriteLn(Format('open: %.3f s, %d kbps', [info.Length, info.Bitrate]));
  if ParamCount >= 2 then
  begin
    WriteLn('seek ', ParamStr(2), ' -> ', nca_seek(StrToFloat(ParamStr(2))));
    WriteLn(Format('position after seek: %.3f', [nca_get_pos]));
  end;
  pos0 := nca_get_pos;
  nca_play;
  for i := 1 to 20 do begin Sleep(100); nca_poll; end;
  pos1 := nca_get_pos;
  WriteLn(Format('played: position %.3f -> %.3f, state %d', [pos0, pos1, nca_state]));
  nca_stop; nca_close; UnloadAudio;
end.
