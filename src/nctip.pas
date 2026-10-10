{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcTip;
{ Native Windows tooltip (comctl32 "tooltips_class32") for areas of a custom-drawn
  window. The tooltip tracks the mouse itself (TTF_SUBCLASS); the font is the
  system tooltip font (NONCLIENTMETRICS.lfStatusFont) for the monitor DPI. }
{$mode objfpc}{$H+}

interface

uses
  Windows, SysUtils;

type
  TNcTip = class
  private
    FOwner, FWnd: HWND;
    FFont: HFONT;
    FDpi, FTools: Integer;
    FText: UnicodeString;
    procedure ApplyFont;
  public
    constructor Create(Owner: HWND);
    destructor Destroy; override;
    { replaces all tool rectangles (client pixels of the owner); none = inactive }
    procedure SetRects(const R: array of TRect);
    procedure SetText(const s: string);
    procedure SetDpi(Dpi: Integer);
    property Owner: HWND read FOwner;
    property Wnd: HWND read FWnd;
  end;

implementation

const
  TTS_ALWAYSTIP = $01;
  TTS_NOPREFIX = $02;
  TTF_SUBCLASS = $0010;
  TTM_ACTIVATE = WM_USER + 1;
  TTM_SETMAXTIPWIDTH = WM_USER + 24;
  TTM_POP = WM_USER + 28;
  TTM_UPDATE = WM_USER + 29;
  TTM_ADDTOOLW = WM_USER + 50;
  TTM_DELTOOLW = WM_USER + 51;
  TTM_UPDATETIPTEXTW = WM_USER + 57;

type
  TToolInfoW = record
    cbSize, uFlags: UINT;
    hwnd: HWND;
    uId: UINT_PTR;
    rect: TRect;
    hinst: HINST;
    lpszText: PWideChar;
    lParam: LPARAM;
    lpReserved: Pointer;
  end;

  TNcMetricsW = record   { NONCLIENTMETRICSW incl. iPaddedBorderWidth (Vista+) }
    cbSize, iBorderWidth, iScrollWidth, iScrollHeight, iCaptionWidth, iCaptionHeight: Integer;
    lfCaptionFont: LOGFONTW;
    iSmCaptionWidth, iSmCaptionHeight: Integer;
    lfSmCaptionFont: LOGFONTW;
    iMenuWidth, iMenuHeight: Integer;
    lfMenuFont, lfStatusFont, lfMessageFont: LOGFONTW;
    iPaddedBorderWidth: Integer;
  end;

  TSpiForDpi = function(uiAction, uiParam: UINT; pvParam: Pointer; fWinIni, dpi: UINT): BOOL; stdcall;

var
  SpiForDpi: TSpiForDpi = nil;

constructor TNcTip.Create(Owner: HWND);
begin
  FOwner := Owner;
  FDpi := 96;
  FWnd := CreateWindowExW(WS_EX_TOPMOST, 'tooltips_class32', nil,
    WS_POPUP or TTS_ALWAYSTIP or TTS_NOPREFIX,
    Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT), Integer(CW_USEDEFAULT),
    Owner, 0, HInstance, nil);
  if FWnd <> 0 then
    SetWindowPos(FWnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
end;

destructor TNcTip.Destroy;
begin
  if FWnd <> 0 then DestroyWindow(FWnd);
  if FFont <> 0 then DeleteObject(FFont);
  inherited Destroy;
end;

procedure TNcTip.ApplyFont;
var
  m: TNcMetricsW;
  ok: Boolean;
  sysDpi: Integer;
  dc: HDC;
  f: HFONT;
begin
  if FWnd = 0 then Exit;
  FillChar(m, SizeOf(m), 0);
  m.cbSize := SizeOf(m);
  ok := Assigned(SpiForDpi) and SpiForDpi(SPI_GETNONCLIENTMETRICS, SizeOf(m), @m, 0, FDpi);
  if not ok then
  begin
    m.cbSize := SizeOf(m);
    ok := SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, SizeOf(m), @m, 0);
    if not ok then
    begin
      m.cbSize := SizeOf(m) - SizeOf(Integer);   { pre-Vista layout }
      ok := SystemParametersInfoW(SPI_GETNONCLIENTMETRICS, m.cbSize, @m, 0);
    end;
    if not ok then Exit;
    { these metrics are at the system DPI: rescale to the monitor DPI }
    dc := GetDC(0);
    sysDpi := GetDeviceCaps(dc, LOGPIXELSY);
    ReleaseDC(0, dc);
    if (sysDpi > 0) and (sysDpi <> FDpi) then
      m.lfStatusFont.lfHeight := MulDiv(m.lfStatusFont.lfHeight, FDpi, sysDpi);
  end;
  f := CreateFontIndirectW(@m.lfStatusFont);
  if f = 0 then Exit;
  SendMessageW(FWnd, WM_SETFONT, WPARAM(f), 1);
  if FFont <> 0 then DeleteObject(FFont);
  FFont := f;
  SendMessageW(FWnd, TTM_SETMAXTIPWIDTH, 0, MulDiv(480, FDpi, 96));   { wrap very long titles }
end;

procedure TNcTip.SetDpi(Dpi: Integer);
begin
  if Dpi <= 0 then Dpi := 96;
  if (Dpi <> FDpi) or (FFont = 0) or
     ((FWnd <> 0) and (HFONT(SendMessageW(FWnd, WM_GETFONT, 0, 0)) <> FFont)) then
  begin
    FDpi := Dpi;
    ApplyFont;
  end;
end;

procedure TNcTip.SetRects(const R: array of TRect);
var
  ti: TToolInfoW;
  i: Integer;
begin
  if FWnd = 0 then Exit;
  FillChar(ti, SizeOf(ti), 0);
  ti.cbSize := SizeOf(ti);
  ti.hwnd := FOwner;
  for i := 1 to FTools do
  begin
    ti.uId := i;
    SendMessageW(FWnd, TTM_DELTOOLW, 0, LPARAM(@ti));
  end;
  FTools := 0;
  for i := 0 to High(R) do
  begin
    if (R[i].Right <= R[i].Left) or (R[i].Bottom <= R[i].Top) then Continue;
    Inc(FTools);
    ti.uFlags := TTF_SUBCLASS;
    ti.uId := FTools;
    ti.rect := R[i];
    ti.hinst := 0;
    ti.lpszText := PWideChar(FText);
    SendMessageW(FWnd, TTM_ADDTOOLW, 0, LPARAM(@ti));
  end;
  SendMessageW(FWnd, TTM_ACTIVATE, WPARAM(FTools > 0), 0);
  if FTools = 0 then SendMessageW(FWnd, TTM_POP, 0, 0);
end;

procedure TNcTip.SetText(const s: string);
var
  ti: TToolInfoW;
  i: Integer;
begin
  if FWnd = 0 then Exit;
  if UTF8Decode(s) = FText then Exit;
  FText := UTF8Decode(s);
  FillChar(ti, SizeOf(ti), 0);
  ti.cbSize := SizeOf(ti);
  ti.hwnd := FOwner;
  ti.lpszText := PWideChar(FText);   { '' = the tooltip does not show }
  for i := 1 to FTools do
  begin
    ti.uId := i;
    SendMessageW(FWnd, TTM_UPDATETIPTEXTW, 0, LPARAM(@ti));
  end;
  if FText = '' then SendMessageW(FWnd, TTM_POP, 0, 0)
  else SendMessageW(FWnd, TTM_UPDATE, 0, 0);       { a visible tip shows the new title }
end;

initialization
  Pointer(SpiForDpi) := GetProcAddress(GetModuleHandle('user32.dll'), 'SystemParametersInfoForDpi');
end.
