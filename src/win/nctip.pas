{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcTip;
{ Self-drawn tooltip for areas of a custom-drawn window: a small topmost popup that
  never activates and is transparent to the mouse, drawn in the player's LCD colours.
  Text uses the system tooltip font (NONCLIENTMETRICS.lfStatusFont) at the monitor
  DPI; padding and border scale with the DPI. Hover timing follows the native
  tooltip (initial delay = double-click time, auto-pop after 10x that). The owner
  calls Poll from its UI timer. }
{$mode objfpc}{$H+}

interface

uses
  Windows, Types, SysUtils, Math;

type
  { optional custom text renderer: Measure=True -> return the text block size in W, H
    (H = visual height to centre); Measure=False -> draw it centred in R }
  TNcTipDraw = procedure(DC: HDC; const R: TRect; const Text: string; Measure: Boolean;
    MaxW: Integer; out W, H: Integer) of object;

  TNcTip = class
  private
    FOwner, FWnd: HWND;
    FFont: HFONT;
    FDpi: Integer;
    FText: UnicodeString;
    FRects: array of TRect;
    FBg, FFg, FBorder: COLORREF;
    FPad, FBw, FTextW, FTextH, FInkTop, FInkH, FLineH, FInkLeft, FWrapW: Integer;
    FShown, FBlocked, FFixed: Boolean;
    FHoverStart, FShownAt: QWord;
    FHoverPt, FAnchor: TPoint;
    FOnDraw: TNcTipDraw;
    procedure ApplyFont;
    procedure Measure;
    procedure MeasureInk(dc: HDC; w, h, Lines: Integer);
    procedure Place;
    procedure Paint(DC: HDC);
    function InTool(const pt: TPoint): Boolean;
  public
    constructor Create(Owner: HWND);
    destructor Destroy; override;
    procedure SetRects(const R: array of TRect);   { client px of the owner; none = off }
    procedure SetText(const s: string);            { '' = never shows }
    procedure SetDpi(Dpi: Integer);
    procedure SetColors(Bg, Fg, Border: COLORREF);
    procedure Poll;
    procedure Hide;
    { shown at once, without hover tracking (a value readout while a control is dragged):
      centred under Anchor (screen px), or above it when there is no room below; Poll
      leaves it alone until Hide }
    procedure ShowFixed(const s: string; const Anchor: TRect);
    property Owner: HWND read FOwner;
    property Wnd: HWND read FWnd;
    property Shown: Boolean read FShown;
    property OnDraw: TNcTipDraw read FOnDraw write FOnDraw;
  end;

implementation

const
  CLASS_NAME: PWideChar = 'NcAmpLcdTip';
  CS_DROPSHADOW = $00020000;
  WS_EX_NOACTIVATE = $08000000;
  DT_FLAGS = DT_WORDBREAK or DT_EDITCONTROL or DT_NOPREFIX;
  TEXT_SCALE = 8 / 9; { text ~1 pt smaller than the system tooltip font (9 -> 8 pt) }
  PAD96 = 7;          { padding on every side at 96 DPI, before TEXT_SCALE }
  MAXW96 = 480;       { wrap width (whole tooltip) at 96 DPI }
  CURSOR96 = 20;      { tooltip top below the hot spot, like the native one }

type
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

  TNcMonInfo = record
    cbSize: DWORD;
    rcMonitor, rcWork: TRect;
    dwFlags: DWORD;
  end;

const
  MONITOR_DEFAULTTONEAREST = 2;

function MonitorFromPoint(pt: TPoint; flags: DWORD): THandle; stdcall; external 'user32.dll';
function GetMonitorInfoW(hMon: THandle; var mi: TNcMonInfo): BOOL; stdcall; external 'user32.dll';

var
  SpiForDpi: TSpiForDpi = nil;
  ClassDone: Boolean = False;

function TipWndProc(h: HWND; msg: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
var
  ps: TPaintStruct;
  t: TNcTip;
  dc: HDC;
begin
  case msg of
    WM_NCHITTEST: Exit(HTTRANSPARENT);
    WM_MOUSEACTIVATE: Exit(MA_NOACTIVATE);
    WM_ERASEBKGND: Exit(1);
    WM_PAINT:
      begin
        dc := BeginPaint(h, @ps);
        t := TNcTip(GetWindowLongPtrW(h, GWLP_USERDATA));
        if t <> nil then t.Paint(dc);
        EndPaint(h, @ps);
        Exit(0);
      end;
  end;
  Result := DefWindowProcW(h, msg, wp, lp);
end;

procedure RegisterTipClass;
var
  wc: WNDCLASSEXW;
begin
  if ClassDone then Exit;
  FillChar(wc, SizeOf(wc), 0);
  wc.cbSize := SizeOf(wc);
  wc.style := CS_DROPSHADOW or CS_SAVEBITS;
  wc.lpfnWndProc := @TipWndProc;
  wc.hInstance := HInstance;
  wc.hCursor := LoadCursor(0, IDC_ARROW);
  wc.lpszClassName := CLASS_NAME;
  ClassDone := RegisterClassExW(wc) <> 0;
end;

constructor TNcTip.Create(Owner: HWND);
begin
  FOwner := Owner;
  FDpi := 96;
  FBg := RGB(255, 255, 225); FFg := RGB(0, 0, 0); FBorder := RGB(0, 0, 0);
  RegisterTipClass;
  FWnd := CreateWindowExW(WS_EX_TOPMOST or WS_EX_TOOLWINDOW or WS_EX_NOACTIVATE, CLASS_NAME, nil,
    WS_POPUP, 0, 0, 10, 10, Owner, 0, HInstance, nil);
  if FWnd <> 0 then SetWindowLongPtrW(FWnd, GWLP_USERDATA, LONG_PTR(Self));
  ApplyFont;
end;

destructor TNcTip.Destroy;
begin
  if FWnd <> 0 then
  begin
    SetWindowLongPtrW(FWnd, GWLP_USERDATA, 0);
    DestroyWindow(FWnd);
  end;
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
    if not ok then
    begin
      FillChar(m.lfStatusFont, SizeOf(m.lfStatusFont), 0);
      m.lfStatusFont.lfHeight := -12;
      m.lfStatusFont.lfCharSet := DEFAULT_CHARSET;
      m.lfStatusFont.lfFaceName := 'Segoe UI';
    end;
    { these metrics are at the system DPI: rescale to the monitor DPI }
    dc := GetDC(0);
    sysDpi := GetDeviceCaps(dc, LOGPIXELSY);
    ReleaseDC(0, dc);
    if (sysDpi > 0) and (sysDpi <> FDpi) then
      m.lfStatusFont.lfHeight := MulDiv(m.lfStatusFont.lfHeight, FDpi, sysDpi);
  end;
  { a little smaller than the system tooltip size, same face }
  m.lfStatusFont.lfHeight := Round(m.lfStatusFont.lfHeight * TEXT_SCALE);
  f := CreateFontIndirectW(@m.lfStatusFont);
  if f = 0 then Exit;
  if FFont <> 0 then DeleteObject(FFont);
  FFont := f;
  FPad := Trunc(PAD96 * TEXT_SCALE * FDpi / 96 + 0.5);   { padding scales with the text; half up }
  FBw := Max(1, Trunc(FDpi / 96 + 0.5));
  Measure;
end;

{ size of the text block; FInkTop/FInkH = where the glyphs of one line really are
  (cap / ideograph top to baseline area), so the padding looks equal above and below }
procedure TNcTip.Measure;
var
  dc, mdc: HDC;
  old, oldB: HGDIOBJ;
  tm: TTextMetricW;
  r: TRect;
  bmi: TBitmapInfo;
  bits: PDWORD;
  bmp: HBITMAP;
  w, h, x, y, top, bot: Integer;
  ref: UnicodeString;
  sz: TSize;
begin
  dc := GetDC(0);
  old := SelectObject(dc, FFont);
  GetTextMetricsW(dc, @tm);
  FLineH := tm.tmHeight;
  { ink box of a reference "H" + ideograph, rendered once per font }
  ref := 'H'#$56FD;   { H国 }
  GetTextExtentPoint32W(dc, PWideChar(ref), Length(ref), @sz);
  w := sz.cx + 4; h := FLineH + 4;
  FillChar(bmi, SizeOf(bmi), 0);
  bmi.bmiHeader.biSize := SizeOf(bmi.bmiHeader);
  bmi.bmiHeader.biWidth := w; bmi.bmiHeader.biHeight := -h;
  bmi.bmiHeader.biPlanes := 1; bmi.bmiHeader.biBitCount := 32;
  bits := nil;
  bmp := CreateDIBSection(dc, bmi, DIB_RGB_COLORS, Pointer(bits), 0, 0);
  FInkTop := tm.tmInternalLeading; FInkH := tm.tmAscent - tm.tmInternalLeading;   { fallback }
  if (bmp <> 0) and (bits <> nil) then
  begin
    mdc := CreateCompatibleDC(dc);
    oldB := SelectObject(mdc, bmp);
    SelectObject(mdc, FFont);
    r := Rect(0, 0, w, h);
    FillRect(mdc, r, GetStockObject(BLACK_BRUSH));
    SetBkMode(mdc, TRANSPARENT);
    SetTextColor(mdc, RGB(255, 255, 255));
    TextOutW(mdc, 2, 2, PWideChar(ref), Length(ref));
    GdiFlush;
    top := -1; bot := -1;
    for y := 0 to h - 1 do
      for x := 0 to w - 1 do
        if (PDWORD(PByte(bits) + (y * w + x) * 4)^ and $FFFFFF) > $303030 then
        begin
          if top < 0 then top := y;
          bot := y;
          Break;
        end;
    if top >= 0 then
    begin
      FInkTop := top - 2;
      FInkH := bot - top + 1;
    end;
    SelectObject(mdc, oldB);
    DeleteDC(mdc);
    DeleteObject(bmp);
  end;
  { the text block itself }
  w := MulDiv(MAXW96, FDpi, 96) - 2 * (FPad + FBw);
  if Assigned(FOnDraw) then
    FOnDraw(dc, Rect(0, 0, w, 0), UTF8Encode(FText), True, w, FTextW, FTextH)
  else
  begin
    FWrapW := w;
    r := Rect(0, 0, w, 0);
    if FText <> '' then
      DrawTextW(dc, PWideChar(FText), Length(FText), r, DT_FLAGS or DT_CALCRECT)
    else
      r := Rect(0, 0, 0, FLineH);
    FTextW := r.Right - r.Left;
    FInkLeft := 0;
    { n lines: (n-1) line heights + the ink height of the last line }
    FTextH := (Max(1, Round((r.Bottom - r.Top) / Max(1, FLineH))) - 1) * FLineH + FInkH;
    { horizontal: use where the glyphs really are (advance widths, overhangs and
      font fallback can differ from the ink), so left and right padding are equal }
    if FText <> '' then
      MeasureInk(dc, r.Right - r.Left + 40, r.Bottom - r.Top + 8,
        Max(1, Round((r.Bottom - r.Top) / Max(1, FLineH))));
  end;
  SelectObject(dc, old);
  ReleaseDC(0, dc);
end;

procedure TNcTip.MeasureInk(dc: HDC; w, h, Lines: Integer);
var
  mdc: HDC;
  bmi: TBitmapInfo;
  bits: Pointer;
  bmp: HBITMAP;
  oldB: HGDIOBJ;
  r: TRect;
  x, y, l, rr, t, b, lim: Integer;
  hit: Boolean;
begin
  if (w <= 0) or (h <= 0) then Exit;
  FillChar(bmi, SizeOf(bmi), 0);
  bmi.bmiHeader.biSize := SizeOf(bmi.bmiHeader);
  bmi.bmiHeader.biWidth := w; bmi.bmiHeader.biHeight := -h;
  bmi.bmiHeader.biPlanes := 1; bmi.bmiHeader.biBitCount := 32;
  bits := nil;
  bmp := CreateDIBSection(dc, bmi, DIB_RGB_COLORS, bits, 0, 0);
  if (bmp = 0) or (bits = nil) then Exit;
  mdc := CreateCompatibleDC(dc);
  oldB := SelectObject(mdc, bmp);
  SelectObject(mdc, FFont);
  r := Rect(0, 0, w, h);
  FillRect(mdc, r, GetStockObject(BLACK_BRUSH));
  SetBkMode(mdc, TRANSPARENT);
  SetTextColor(mdc, RGB(255, 255, 255));
  r := Rect(4, 2, 4 + FWrapW, h);    { same wrap width as when painting }
  DrawTextW(mdc, PWideChar(FText), Length(FText), r, DT_FLAGS);
  GdiFlush;
  l := -1; rr := -1;
  for x := 0 to w - 1 do
    for y := 0 to h - 1 do
      if (PDWORD(PByte(bits) + (y * w + x) * 4)^ and $FFFFFF) > $303030 then
      begin
        if l < 0 then l := x;
        rr := x;
        Break;
      end;
  if l >= 0 then
  begin
    FInkLeft := l - 4;
    FTextW := rr - l + 1;
  end;
  { vertical: top of the real glyphs on the first line; bottom of the glyphs on the
    last line, but not below the reference ideograph bottom (descenders such as
    g / y hang into the padding, as in normal typography) }
  lim := 2 + (Lines - 1) * FLineH + FInkTop + FInkH - 1;
  t := -1; b := -1;
  for y := 0 to Min(h - 1, lim) do
  begin
    hit := False;
    for x := 0 to w - 1 do
      if (PDWORD(PByte(bits) + (y * w + x) * 4)^ and $FFFFFF) > $303030 then
      begin
        hit := True;
        Break;
      end;
    if hit then
    begin
      if t < 0 then t := y;
      b := y;
    end;
  end;
  if (t >= 0) and (b >= t) then
  begin
    FInkTop := t - 2;
    FTextH := b - t + 1;
  end;
  SelectObject(mdc, oldB);
  DeleteDC(mdc);
  DeleteObject(bmp);
end;

procedure TNcTip.Paint(DC: HDC);
var
  r, tr: TRect;
  br: HBRUSH;
  old: HGDIOBJ;
  w, h: Integer;
  mdc: HDC;
  bmp: HBITMAP;
  oldB: HGDIOBJ;
begin
  GetClientRect(FWnd, r);
  { double-buffered }
  mdc := CreateCompatibleDC(DC);
  bmp := CreateCompatibleBitmap(DC, r.Right, r.Bottom);
  oldB := SelectObject(mdc, bmp);
  br := CreateSolidBrush(FBorder);
  FillRect(mdc, r, br);
  DeleteObject(br);
  tr := r;
  InflateRect(tr, -FBw, -FBw);
  br := CreateSolidBrush(FBg);
  FillRect(mdc, tr, br);
  DeleteObject(br);
  InflateRect(tr, -FPad, -FPad);
  SetBkMode(mdc, TRANSPARENT);
  SetTextColor(mdc, FFg);
  old := SelectObject(mdc, FFont);
  if Assigned(FOnDraw) then
    FOnDraw(mdc, tr, UTF8Encode(FText), False, tr.Right - tr.Left, w, h)
  else
  begin
    { first line's glyph tops sit exactly FPad below the border }
    OffsetRect(tr, -FInkLeft, -FInkTop);
    tr.Right := tr.Left + FWrapW;             { wrap exactly as measured }
    tr.Bottom := tr.Top + FTextH + FLineH;   { room for descenders }
    DrawTextW(mdc, PWideChar(FText), Length(FText), tr, DT_FLAGS);
  end;
  SelectObject(mdc, old);
  BitBlt(DC, 0, 0, r.Right, r.Bottom, mdc, 0, 0, SRCCOPY);
  SelectObject(mdc, oldB);
  DeleteObject(bmp);
  DeleteDC(mdc);
end;

procedure TNcTip.Place;
var
  w, h, x, y: Integer;
  mi: TNcMonInfo;
  wa: TRect;
begin
  w := FTextW + 2 * (FPad + FBw);
  h := FTextH + 2 * (FPad + FBw);
  x := FAnchor.X;
  y := FAnchor.Y + Round(CURSOR96 * FDpi / 96);
  mi.cbSize := SizeOf(mi);
  if GetMonitorInfoW(MonitorFromPoint(FAnchor, MONITOR_DEFAULTTONEAREST), mi) then
  begin
    wa := mi.rcWork;
    if x + w > wa.Right then x := wa.Right - w;
    if x < wa.Left then x := wa.Left;
    if y + h > wa.Bottom then y := FAnchor.Y - h - Round(4 * FDpi / 96);   { flip above }
    if y < wa.Top then y := wa.Top;
  end;
  SetWindowPos(FWnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE or SWP_NOOWNERZORDER);
end;

function TNcTip.InTool(const pt: TPoint): Boolean;
var
  h: HWND;
  c: TPoint;
  i: Integer;
begin
  Result := False;
  if (Length(FRects) = 0) or (FText = '') or not IsWindowVisible(FOwner) then Exit;
  h := WindowFromPoint(pt);
  if h <> FOwner then Exit;
  c := pt;
  ScreenToClient(FOwner, c);
  for i := 0 to High(FRects) do
    if PtInRect(FRects[i], c) then Exit(True);
end;

procedure TNcTip.Hide;
begin
  if FShown and (FWnd <> 0) then ShowWindow(FWnd, SW_HIDE);
  FShown := False;
  FFixed := False;
end;

procedure TNcTip.ShowFixed(const s: string; const Anchor: TRect);
var
  w, h, x, y, gap: Integer;
  mi: TNcMonInfo;
  wa: TRect;
  t: UnicodeString;
begin
  if FWnd = 0 then Exit;
  t := UTF8Decode(s);
  if t = '' then begin Hide; Exit; end;
  if (t <> FText) or not FFixed then begin FText := t; Measure; end;
  FFixed := True;
  w := FTextW + 2 * (FPad + FBw);
  h := FTextH + 2 * (FPad + FBw);
  gap := Round(3 * FDpi / 96);
  x := (Anchor.Left + Anchor.Right - w) div 2;
  y := Anchor.Bottom + gap;
  mi.cbSize := SizeOf(mi);
  if GetMonitorInfoW(MonitorFromPoint(Point((Anchor.Left + Anchor.Right) div 2, Anchor.Bottom), MONITOR_DEFAULTTONEAREST), mi) then
  begin
    wa := mi.rcWork;
    if y + h > wa.Bottom then y := Anchor.Top - gap - h;   { flip above }
    if x + w > wa.Right then x := wa.Right - w;
    if x < wa.Left then x := wa.Left;
    if y < wa.Top then y := wa.Top;
  end;
  SetWindowPos(FWnd, HWND_TOPMOST, x, y, w, h, SWP_NOACTIVATE or SWP_NOOWNERZORDER);
  InvalidateRect(FWnd, nil, False);
  if not FShown then ShowWindow(FWnd, SW_SHOWNOACTIVATE);
  FShown := True;
  FShownAt := GetTickCount64;
end;

procedure TNcTip.Poll;
var
  pt: TPoint;
  now: QWord;
  delay: UINT;
begin
  if (FWnd = 0) or FFixed then Exit;
  if not GetCursorPos(pt) then Exit;
  now := GetTickCount64;
  if not InTool(pt) then
  begin
    Hide;
    FBlocked := False;
    FHoverStart := 0;
    Exit;
  end;
  if (GetAsyncKeyState(VK_LBUTTON) < 0) or (GetAsyncKeyState(VK_RBUTTON) < 0) or
     (GetAsyncKeyState(VK_MBUTTON) < 0) then
  begin
    Hide;                  { clicked / dragging: stay hidden until the mouse leaves }
    FBlocked := True;
    Exit;
  end;
  if FBlocked then Exit;
  delay := GetDoubleClickTime;
  if FShown then
  begin
    if now - FShownAt >= 10 * delay then
    begin
      Hide;                { auto-pop, like the native tooltip }
      FBlocked := True;
    end;
    Exit;
  end;
  if (FHoverStart = 0) or (Abs(pt.X - FHoverPt.X) > 2) or (Abs(pt.Y - FHoverPt.Y) > 2) then
  begin
    FHoverStart := now;    { the mouse must rest for the initial delay }
    FHoverPt := pt;
    Exit;
  end;
  if now - FHoverStart >= delay then
  begin
    FAnchor := pt;
    Measure;
    Place;
    InvalidateRect(FWnd, nil, False);
    ShowWindow(FWnd, SW_SHOWNOACTIVATE);
    FShown := True;
    FShownAt := now;
  end;
end;

procedure TNcTip.SetDpi(Dpi: Integer);
begin
  if Dpi <= 0 then Dpi := 96;
  if (Dpi <> FDpi) or (FFont = 0) then
  begin
    FDpi := Dpi;
    ApplyFont;
    if FShown then begin Place; InvalidateRect(FWnd, nil, False); end;
  end;
end;

procedure TNcTip.SetColors(Bg, Fg, Border: COLORREF);
begin
  FBg := Bg; FFg := Fg; FBorder := Border;
  if FShown then InvalidateRect(FWnd, nil, False);
end;

procedure TNcTip.SetRects(const R: array of TRect);
var
  i, n: Integer;
begin
  SetLength(FRects, Length(R));
  n := 0;
  for i := 0 to High(R) do
    if (R[i].Right > R[i].Left) and (R[i].Bottom > R[i].Top) then
    begin
      FRects[n] := R[i];
      Inc(n);
    end;
  SetLength(FRects, n);
  if n = 0 then Hide;
end;

procedure TNcTip.SetText(const s: string);
begin
  if UTF8Decode(s) = FText then Exit;
  FText := UTF8Decode(s);
  if FText = '' then begin Hide; Exit; end;
  if FShown then
  begin
    Measure;               { new track while shown: resize in place }
    Place;
    InvalidateRect(FWnd, nil, False);
  end;
end;

initialization
  Pointer(SpiForDpi) := GetProcAddress(GetModuleHandle('user32.dll'), 'SystemParametersInfoForDpi');
end.
