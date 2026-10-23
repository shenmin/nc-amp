{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcTray;
{ Notification-area icon done directly with Shell_NotifyIconW (NOTIFYICON_VERSION_4)
  on our own hidden per-monitor-v2 window, plus helpers so popup menus are owned by a
  window that lives on the monitor where the menu appears (correct DPI / system font).
  No LCL TTrayIcon, no owner-draw. }
{$mode objfpc}{$H+}
{$PACKRECORDS C}

interface

uses Windows, Messages, SysUtils;

type
  TTrayClickEvent = procedure of object;
  TTrayMenuEvent = procedure(X, Y: Integer) of object;
  TTrayLogEvent = procedure(const s: string) of object;

  TNcTray = class
  private
    FWnd: HWND;
    FIcon: HICON;
    FIconSize: Integer;
    FTip: UnicodeString;
    FV4, FAdded: Boolean;
    procedure Notify(Msg: DWORD; Flags: UINT);
    procedure ReloadIcon;
    procedure Log(const s: string);
  public
    OnClick: TTrayClickEvent;
    OnMenu: TTrayMenuEvent;
    OnLog: TTrayLogEvent;
    constructor Create(const Tip: string);
    destructor Destroy; override;
    procedure Show;
    procedure SetTip(const s: string);
    property Wnd: HWND read FWnd;
    property IconSize: Integer read FIconSize;
    property Version4: Boolean read FV4;
  end;

{ hidden 1x1 PMv2 window created ON the monitor containing (X, Y): its DPI is that
  monitor's DPI, so a menu tracked with it is laid out for that monitor }
function CreateMenuOwner(X, Y: Integer): HWND;
{ run the following code with a per-monitor-v2 thread DPI context; returns the old one }
function BeginPMv2: THandle;
procedure EndPMv2(Old: THandle);
function WindowDpi(h: HWND): Integer;
function ThreadAwarenessName: string;

implementation

type
  TNotifyIconDataW4 = record
    cbSize: DWORD;
    Wnd: HWND;
    uID: UINT;
    uFlags: UINT;
    uCallbackMessage: UINT;
    hIcon: HICON;
    szTip: array[0..127] of WideChar;
    dwState: DWORD;
    dwStateMask: DWORD;
    szInfo: array[0..255] of WideChar;
    uVersion: UINT;
    szInfoTitle: array[0..63] of WideChar;
    dwInfoFlags: DWORD;
    guidItem: TGUID;
    hBalloonIcon: HICON;
  end;

  TSetThreadCtx = function(ctx: THandle): THandle; stdcall;
  TGetThreadCtx = function: THandle; stdcall;
  TGetAwarenessFromCtx = function(ctx: THandle): Integer; stdcall;
  TGetDpiForWindow = function(h: HWND): UINT; stdcall;
  TGetSysMetricsForDpi = function(idx: Integer; dpi: UINT): Integer; stdcall;
  TGetDpiForMonitor = function(mon: HMONITOR; kind: Integer; out dx, dy: UINT): HRESULT; stdcall;
  TLoadIconWithScaleDown = function(inst: HINST; name: PWideChar; cx, cy: Integer; out ico: HICON): HRESULT; stdcall;

const
  NIM_ADD = 0; NIM_MODIFY = 1; NIM_DELETE = 2; NIM_SETVERSION = 4;
  NIF_MESSAGE = 1; NIF_ICON = 2; NIF_TIP = 4; NIF_SHOWTIP = $80;
  NOTIFYICON_VERSION_4 = 4;
  NIN_SELECT = WM_USER + 0;
  NIN_KEYSELECT = WM_USER + 1;
  WM_NCTRAY = WM_APP + 41;
  TRAY_ID = 1;
  WM_DPICHANGED_ = $02E0;
  CTX_PMV2 = THandle(-4);

function MonitorFromPoint_(pt: TPoint; flags: DWORD): HMONITOR; stdcall;
  external 'user32.dll' name 'MonitorFromPoint';

function Shell_NotifyIconW_(dwMessage: DWORD; lpData: Pointer): BOOL; stdcall;
  external 'shell32.dll' name 'Shell_NotifyIconW';

var
  GTray: TNcTray = nil;
  WM_TASKBARCREATED: UINT = 0;
  pSetThreadCtx: TSetThreadCtx = nil;
  pGetThreadCtx: TGetThreadCtx = nil;
  pAwareness: TGetAwarenessFromCtx = nil;
  pGetDpiForWindow: TGetDpiForWindow = nil;
  pSysMetricsForDpi: TGetSysMetricsForDpi = nil;
  pGetDpiForMonitor: TGetDpiForMonitor = nil;
  pLoadIconScaleDown: TLoadIconWithScaleDown = nil;
  ClassesDone: Boolean = False;

procedure LoadApis;
var
  u, h: HMODULE;
begin
  u := GetModuleHandle('user32.dll');
  Pointer(pSetThreadCtx) := GetProcAddress(u, 'SetThreadDpiAwarenessContext');
  Pointer(pGetThreadCtx) := GetProcAddress(u, 'GetThreadDpiAwarenessContext');
  Pointer(pAwareness) := GetProcAddress(u, 'GetAwarenessFromDpiAwarenessContext');
  Pointer(pGetDpiForWindow) := GetProcAddress(u, 'GetDpiForWindow');
  Pointer(pSysMetricsForDpi) := GetProcAddress(u, 'GetSystemMetricsForDpi');
  h := LoadLibrary('shcore.dll');
  if h <> 0 then Pointer(pGetDpiForMonitor) := GetProcAddress(h, 'GetDpiForMonitor');
  h := LoadLibrary('comctl32.dll');
  if h <> 0 then Pointer(pLoadIconScaleDown) := GetProcAddress(h, 'LoadIconWithScaleDown');
end;

function BeginPMv2: THandle;
begin
  Result := 0;
  if Assigned(pSetThreadCtx) then Result := pSetThreadCtx(CTX_PMV2);
end;

procedure EndPMv2(Old: THandle);
begin
  if Assigned(pSetThreadCtx) and (Old <> 0) then pSetThreadCtx(Old);
end;

function ThreadAwarenessName: string;
var
  a: Integer;
begin
  Result := 'n/a';
  if not (Assigned(pGetThreadCtx) and Assigned(pAwareness)) then Exit;
  a := pAwareness(pGetThreadCtx());
  case a of
    0: Result := 'unaware';
    1: Result := 'system-aware';
    2: Result := 'per-monitor-aware';
  else Result := IntToStr(a);
  end;
end;

function WindowDpi(h: HWND): Integer;
var
  dc: HDC;
begin
  if Assigned(pGetDpiForWindow) and (h <> 0) then Result := pGetDpiForWindow(h)
  else
  begin
    dc := GetDC(0);
    Result := GetDeviceCaps(dc, LOGPIXELSX);
    ReleaseDC(0, dc);
  end;
  if Result <= 0 then Result := 96;
end;

function TrayWndProc(h: HWND; msg: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
var
  pt: TPoint;
begin
  Result := 0;
  if (GTray <> nil) and (h = GTray.FWnd) then
  begin
    if msg = WM_NCTRAY then
    begin
      case LOWORD(lp) of
        NIN_SELECT, NIN_KEYSELECT:
          if Assigned(GTray.OnClick) then GTray.OnClick();
        WM_LBUTTONUP:
          if (not GTray.FV4) and Assigned(GTray.OnClick) then GTray.OnClick();
        WM_CONTEXTMENU:
          if Assigned(GTray.OnMenu) then
            GTray.OnMenu(SmallInt(LOWORD(wp)), SmallInt(HIWORD(wp)));   { v4: anchor point in wParam }
        WM_RBUTTONUP:
          if (not GTray.FV4) and Assigned(GTray.OnMenu) then
          begin
            GetCursorPos(pt);
            GTray.OnMenu(pt.X, pt.Y);
          end;
      end;
      Exit;
    end;
    if (WM_TASKBARCREATED <> 0) and (msg = WM_TASKBARCREATED) then
    begin
      { Explorer restarted, or the taskbar DPI changed: add again with a fresh icon }
      GTray.FAdded := False;
      GTray.ReloadIcon;
      GTray.Show;
      Exit;
    end;
    if (msg = WM_DPICHANGED_) or (msg = WM_DISPLAYCHANGE) or (msg = WM_SETTINGCHANGE) then
    begin
      GTray.ReloadIcon;
      if GTray.FAdded then GTray.Notify(NIM_MODIFY, NIF_ICON);
    end;
  end;
  Result := DefWindowProcW(h, msg, wp, lp);
end;

function MenuOwnerProc(h: HWND; msg: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
begin
  Result := DefWindowProcW(h, msg, wp, lp);
end;

procedure RegisterClasses;
var
  wc: TWndClassExW;
begin
  if ClassesDone then Exit;
  ClassesDone := True;
  FillChar(wc, SizeOf(wc), 0);
  wc.cbSize := SizeOf(wc);
  wc.lpfnWndProc := @TrayWndProc;
  wc.hInstance := HInstance;
  wc.lpszClassName := 'ncamp_tray';
  RegisterClassExW(wc);
  wc.lpfnWndProc := @MenuOwnerProc;
  wc.lpszClassName := 'ncamp_menuowner';
  RegisterClassExW(wc);
end;

function CreateMenuOwner(X, Y: Integer): HWND;
var
  old: THandle;
begin
  RegisterClasses;
  old := BeginPMv2;
  try
    { never shown; position decides its monitor and therefore its DPI }
    { 1x1, fully transparent layered tool window: shown (so it can really become the
      foreground window and the menu gets keyboard / click-away dismissal) but invisible }
    Result := CreateWindowExW(WS_EX_TOOLWINDOW or WS_EX_LAYERED or WS_EX_TOPMOST,
      'ncamp_menuowner', 'nc-amp menu', WS_POPUP, X, Y, 1, 1, 0, 0, HInstance, nil);
    if Result <> 0 then
    begin
      SetLayeredWindowAttributes(Result, 0, 0, LWA_ALPHA);
      ShowWindow(Result, SW_SHOWNA);
    end;
  finally
    EndPMv2(old);
  end;
end;

{ TNcTray }

constructor TNcTray.Create(const Tip: string);
var
  old: THandle;
begin
  inherited Create;
  GTray := Self;
  RegisterClasses;
  WM_TASKBARCREATED := RegisterWindowMessageW('TaskbarCreated');
  FTip := UTF8Decode(Tip);
  old := BeginPMv2;
  try
    { hidden top-level window (not message-only, so it gets the TaskbarCreated
      broadcast), created with a per-monitor-v2 thread context on the primary monitor }
    FWnd := CreateWindowExW(WS_EX_TOOLWINDOW, 'ncamp_tray', 'nc-amp tray', WS_POPUP,
      0, 0, 1, 1, 0, 0, HInstance, nil);
  finally
    EndPMv2(old);
  end;
  ReloadIcon;
end;

destructor TNcTray.Destroy;
begin
  if FAdded then Notify(NIM_DELETE, 0);
  if FIcon <> 0 then DestroyIcon(FIcon);
  if FWnd <> 0 then DestroyWindow(FWnd);
  GTray := nil;
  inherited Destroy;
end;

procedure TNcTray.Log(const s: string);
begin
  if Assigned(OnLog) then OnLog(s);
end;

procedure TNcTray.ReloadIcon;
var
  dpi: UINT;
  dx, dy: UINT;
  sz: Integer;
  ico: HICON;
  mon: HMONITOR;
  p0: TPoint;
begin
  { the notification area is on the primary taskbar: use the primary monitor's DPI }
  dpi := 0;
  if Assigned(pGetDpiForMonitor) then
  begin
    p0.X := 0; p0.Y := 0;
    mon := MonitorFromPoint_(p0, 1 { MONITOR_DEFAULTTOPRIMARY });
    if pGetDpiForMonitor(mon, 0, dx, dy) = S_OK then dpi := dx;
  end;
  if dpi = 0 then dpi := WindowDpi(FWnd);
  if Assigned(pSysMetricsForDpi) then sz := pSysMetricsForDpi(SM_CXSMICON, dpi)
  else sz := MulDiv(GetSystemMetrics(SM_CXSMICON), dpi, 96);
  if sz <= 0 then sz := 16;
  if (sz = FIconSize) and (FIcon <> 0) then Exit;
  ico := 0;
  if Assigned(pLoadIconScaleDown) then
    if pLoadIconScaleDown(HInstance, 'MAINICON', sz, sz, ico) <> S_OK then ico := 0;
  if ico = 0 then
    ico := LoadImageW(HInstance, 'MAINICON', IMAGE_ICON, sz, sz, LR_DEFAULTCOLOR);
  if ico <> 0 then
  begin
    if FIcon <> 0 then DestroyIcon(FIcon);
    FIcon := ico;
    FIconSize := sz;
  end;
  Log(Format('tray icon: dpi=%d size=%dx%d handle=%s', [dpi, sz, sz, BoolToStr(ico <> 0, True)]));
end;

procedure TNcTray.Notify(Msg: DWORD; Flags: UINT);
var
  d: TNotifyIconDataW4;
  n: Integer;
begin
  FillChar(d, SizeOf(d), 0);
  d.cbSize := SizeOf(d);
  d.Wnd := FWnd;
  d.uID := TRAY_ID;
  d.uFlags := Flags;
  d.uCallbackMessage := WM_NCTRAY;
  d.hIcon := FIcon;
  n := Length(FTip);
  if n > 127 then n := 127;
  if n > 0 then Move(FTip[1], d.szTip[0], n * SizeOf(WideChar));
  d.uVersion := NOTIFYICON_VERSION_4;
  if Msg = NIM_ADD then
  begin
    FAdded := Shell_NotifyIconW_(NIM_ADD, @d);
    if FAdded then FV4 := Shell_NotifyIconW_(NIM_SETVERSION, @d);
    Log(Format('tray add=%s version4=%s cbSize=%d icon=%dx%d', [BoolToStr(FAdded, True), BoolToStr(FV4, True), d.cbSize, FIconSize, FIconSize]));
  end
  else
    Shell_NotifyIconW_(Msg, @d);
end;

procedure TNcTray.Show;
begin
  if not FAdded then Notify(NIM_ADD, NIF_MESSAGE or NIF_ICON or NIF_TIP or NIF_SHOWTIP);
end;

procedure TNcTray.SetTip(const s: string);
var
  w: UnicodeString;
begin
  w := UTF8Decode(s);
  if w = FTip then Exit;
  FTip := w;
  if FAdded then Notify(NIM_MODIFY, NIF_TIP or NIF_SHOWTIP);
end;

initialization
  LoadApis;
end.
