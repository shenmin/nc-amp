{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
program ncamp;

{$mode objfpc}{$H+}
{$WARN SYMBOL_PLATFORM OFF}

uses
  DpiInit,    // per-monitor DPI awareness before any window exists
  Interfaces, // this includes the LCL widgetset
  Forms, SingleInst, MainForm, NcAudio, TagReader;

{$R *.res}
{$R ncamp.res}  // manifest + LCD font, built from ncamp.rc (see build.sh)

begin
  { one instance per session: a second one forwards its files and quits here,
    before any window or tray icon exists }
  if not IsPrimaryInstance then Exit;
  RequireDerivedFormResource := True;
  Application.Title := 'nc-amp';
  Application.Scaled := False;   // we do our own per-monitor DPI scaling
  Application.MainFormOnTaskBar := True;
  Application.Initialize;
  Application.CreateForm(TMainForm, Form1);
  Application.Run;
end.
