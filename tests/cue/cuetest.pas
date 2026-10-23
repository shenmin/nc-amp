{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min

  Console test of the CUE support with the real engine (Windows under Wine or on Windows, macOS):
    cuetest album.cue [tone-test]
  parses the sheet, then for every track: opens the file, sets the range, checks the length, the
  position after a seek (relative to the track), plays the last 1.5 s and checks that the engine ends
  the track at its end. With "tone-test" it also checks the pitch of the audio (tests/cue/make-cue-test.sh
  makes an album of five sine tones 220 / 330 / 440 / 550 / 660 Hz, track n = tone n). }
program cuetest;
{$mode objfpc}{$H+}
uses SysUtils, NcAudio, CueSheet;

const
  TONES: array[1..5] of Double = (220, 330, 440, 550, 660);

var
  tr: TCueTracks;
  sk, i, k, bad, bestBin, expBin, n: Integer;
  info: TNcaInfo;
  len, expLen, p, t0: Double;
  fft: array[0..511] of Single;
  best: Single;
  tone: Boolean;
  st: Integer;
  ok: Boolean;

procedure Check(c: Boolean; const msg: string);
begin
  if c then WriteLn('  ok   ', msg) else begin WriteLn('  FAIL ', msg); Inc(bad); end;
end;

begin
  if ParamCount < 1 then begin WriteLn('usage: cuetest file.cue [tone-test]'); Halt(2); end;
  tone := (ParamCount >= 2) and (ParamStr(2) = 'tone-test');
  bad := 0;
  LoadAudio;
  WriteLn('engine: ', AudioVersion, '; device ready: ', AudioReady);
  if not ParseCueFile(ParamStr(1), tr, sk) then begin WriteLn('FAIL cannot read the sheet'); Halt(1); end;
  WriteLn('tracks: ', Length(tr), ', skipped: ', sk);
  for i := 0 to High(tr) do
  begin
    WriteLn(Format('#%d "%s" - "%s"  %s  %.4f .. %.4f', [tr[i].Number, tr[i].Performer, tr[i].Title,
      ExtractFileName(tr[i].Audio), tr[i].Start, tr[i].Stop]));
    FillChar(info, SizeOf(info), 0);
    if nca_open_utf8(tr[i].Audio, @info) = 0 then begin Check(False, 'open'); Continue; end;
    Check(nca_set_range(tr[i].Start, tr[i].Stop) <> 0, 'set range');
    len := nca_get_len;
    if tr[i].Stop > 0 then expLen := tr[i].Stop - tr[i].Start else expLen := info.Length - tr[i].Start;
    Check(Abs(len - expLen) < 0.05, Format('length %.3f (expected %.3f)', [len, expLen]));
    Check(Abs(nca_get_pos) < 0.01, Format('position at the start %.3f', [nca_get_pos]));
    nca_seek(1.0);
    Check(Abs(nca_get_pos - 1.0) < 0.05, Format('position after seek(1.0) = %.3f', [nca_get_pos]));
    { play the last 1.5 s: the engine must end the track exactly at its end }
    nca_seek(len - 1.5);
    nca_play;
    if tone then
    begin
      Sleep(400); nca_poll;
      FillChar(fft, SizeOf(fft), 0);
      nca_get_fft(@fft[0]);
      best := 0; bestBin := 0;
      for k := 1 to 511 do if fft[k] > best then begin best := fft[k]; bestBin := k; end;
      n := tr[i].Number; if n > 5 then n := 5;
      expBin := Round(TONES[n] * 1024 / info.SampleRate);
      Check(Abs(bestBin - expBin) <= 1, Format('pitch: strongest bin %d, expected %d (tone %.0f Hz)', [bestBin, expBin, TONES[n]]));
    end;
    t0 := Now;
    ok := False;
    for k := 1 to 80 do
    begin
      Sleep(50); nca_poll;
      st := nca_state;
      if st = NCA_ENDED then begin ok := True; Break; end;
    end;
    p := nca_get_pos;
    Check(ok and (Abs(p - len) < 0.05), Format('ended at %.3f of %.3f (state %d)', [p, len, nca_state]));
    nca_close;
  end;
  UnloadAudio;
  if bad = 0 then WriteLn('ALL OK') else WriteLn(bad, ' FAILED');
  Halt(Ord(bad > 0));
end.
