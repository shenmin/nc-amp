{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit SingleInst;
{ One nc-amp per user session.
  - IsPrimaryInstance: named mutex 'Local\nc-amp-single-instance'. A second instance
    forwards its command-line paths (UTF-16, WM_COPYDATA) to the first instance's
    message-only window - retrying ~2 s while the first one is still starting -,
    allows it to take the foreground, and returns False so the program exits before
    any window or tray icon exists.
  - StartIpcServer: the first instance's receiving window. }
{$mode objfpc}{$H+}

interface

uses Windows, Messages, SysUtils, Classes;

type
  TIpcEvent = procedure(Paths: TStrings) of object;   { empty list = just activate }

function IsPrimaryInstance: Boolean;
procedure StartIpcServer(OnRequest: TIpcEvent);
procedure StopIpcServer;

implementation

const
  MUTEX_NAME = 'Local\nc-amp-single-instance';
  IPC_CLASS = 'ncamp_ipc_v1';
  IPC_MAGIC = $4E43414D;   { 'NCAM' }
  HWND_MESSAGE = HWND(-3);

var
  GMutex: THandle = 0;
  GWnd: HWND = 0;
  GOnRequest: TIpcEvent = nil;

function AllowSetForegroundWindow_(pid: DWORD): BOOL; stdcall;
  external 'user32.dll' name 'AllowSetForegroundWindow';

procedure Log(const s: string);
var
  fn: string;
  f: TextFile;
begin
  fn := GetEnvironmentVariable('NCAMP_LOG');
  if fn = '' then Exit;
  AssignFile(f, fn);
  try
    if FileExists(fn) then Append(f) else Rewrite(f);
    WriteLn(f, FormatDateTime('hh:nn:ss.zzz', Now), ' [pid ', GetCurrentProcessId, '] ', s);
    CloseFile(f);
  except
  end;
end;

function IsPrimaryInstance: Boolean;
var
  payload: UnicodeString;
  i, tries: Integer;
  target: HWND;
  pid: DWORD;
  cds: TCopyDataStruct;
  res: DWORD_PTR;
  p: string;
begin
  GMutex := CreateMutexW(nil, False, MUTEX_NAME);
  if (GMutex <> 0) and (GetLastError <> ERROR_ALREADY_EXISTS) then
    Exit(True);                       { we are the one }
  { second instance: collect absolute paths (relative to OUR working directory) }
  payload := '';
  for i := 1 to ParamCount do
  begin
    p := ParamStr(i);
    if p = '' then Continue;
    p := ExpandFileName(p);
    Log('second instance arg: ' + p);
    payload := payload + UTF8Decode(p) + #0;
  end;
  payload := payload + #0;
  { the first instance may still be starting: wait up to ~2 s for its window }
  target := 0;
  for tries := 1 to 40 do
  begin
    target := FindWindowExW(HWND_MESSAGE, 0, IPC_CLASS, nil);
    if target <> 0 then Break;
    Sleep(50);
  end;
  Log(Format('second instance: %d path(s), target window=%x after %d tries', [ParamCount, PtrUInt(target), tries]));
  if target <> 0 then
  begin
    pid := 0;
    GetWindowThreadProcessId(target, @pid);
    if pid <> 0 then AllowSetForegroundWindow_(pid);   { let it come to the front }
    cds.dwData := IPC_MAGIC;
    cds.cbData := Length(payload) * SizeOf(WideChar);
    cds.lpData := PWideChar(payload);
    res := 0;
    SendMessageTimeoutW(target, WM_COPYDATA, 0, LPARAM(@cds), SMTO_ABORTIFHUNG, 5000, @res);
    Log('forwarded, result=' + IntToStr(res));
  end;
  Result := False;                     { exit: one instance only }
end;

function IpcWndProc(h: HWND; msg: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
var
  cds: PCopyDataStruct;
  w: PWideChar;
  n, i, st: Integer;
  sl: TStringList;
begin
  if msg = WM_COPYDATA then
  begin
    cds := PCopyDataStruct(lp);
    if (cds <> nil) and (cds^.dwData = IPC_MAGIC) then
    begin
      sl := TStringList.Create;
      try
        w := PWideChar(cds^.lpData);
        n := cds^.cbData div SizeOf(WideChar);
        st := 0;
        for i := 0 to n - 1 do
          if w[i] = #0 then
          begin
            if i > st then sl.Add(UTF8Encode(Copy(UnicodeString(w), st + 1, i - st)));
            st := i + 1;
          end;
        Log(Format('ipc: received %d path(s)', [sl.Count]));
        if Assigned(GOnRequest) then GOnRequest(sl);   { must copy what it needs }
      finally
        sl.Free;
      end;
      Exit(1);
    end;
  end;
  Result := DefWindowProcW(h, msg, wp, lp);
end;

procedure StartIpcServer(OnRequest: TIpcEvent);
var
  wc: TWndClassExW;
begin
  GOnRequest := OnRequest;
  if GWnd <> 0 then Exit;
  FillChar(wc, SizeOf(wc), 0);
  wc.cbSize := SizeOf(wc);
  wc.lpfnWndProc := @IpcWndProc;
  wc.hInstance := HInstance;
  wc.lpszClassName := IPC_CLASS;
  RegisterClassExW(wc);
  GWnd := CreateWindowExW(0, IPC_CLASS, 'nc-amp ipc', 0, 0, 0, 0, 0, HWND_MESSAGE, 0, HInstance, nil);
  Log('ipc server window=' + IntToHex(PtrUInt(GWnd), 1));
end;

procedure StopIpcServer;
begin
  GOnRequest := nil;
  if GWnd <> 0 then DestroyWindow(GWnd);
  GWnd := 0;
end;

finalization
  if GMutex <> 0 then CloseHandle(GMutex);
end.
