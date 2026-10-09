{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit DpiInit;
{ Must be the first unit in the program's uses clause: makes the process
  per-monitor-v2 DPI aware before any window is created. The manifest already
  requests this; this call is a fallback (it fails harmlessly if already set). }
{$mode objfpc}{$H+}

interface

implementation

uses Windows;

type
  TSetCtx = function(ctx: THandle): BOOL; stdcall;
  TSetAwareness = function(v: Integer): HRESULT; stdcall;

procedure Init;
var
  f: TSetCtx;
  g: TSetAwareness;
  h: HMODULE;
begin
  Pointer(f) := GetProcAddress(GetModuleHandle('user32.dll'), 'SetProcessDpiAwarenessContext');
  if Assigned(f) then
  begin
    if not f(THandle(-4)) then   { DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 }
      f(THandle(-3));            { DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE }
    Exit;
  end;
  h := LoadLibrary('shcore.dll');
  if h <> 0 then
  begin
    Pointer(g) := GetProcAddress(h, 'SetProcessDpiAwareness');
    if Assigned(g) then g(2);    { PROCESS_PER_MONITOR_DPI_AWARE }
  end;
end;

initialization
  Init;
end.
