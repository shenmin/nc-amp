{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcTip;
{ Self-drawn tooltip for areas of a custom-drawn window (macOS): a small borderless, non-activating
  NSPanel that ignores the mouse, in the player's LCD colours, with the system font at 12 pt.
  Hover timing follows the native tooltip (initial delay = double-click interval, auto-pop after
  10x that). The owner calls Poll from its UI timer. Same interface as the Windows unit;
  coordinates are in points (the owner's client area / LCL screen coordinates, y down). }
{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses Classes, Types, SysUtils, Math, LCLType;

type
  { optional custom text renderer (Windows only; ignored here) }
  TNcTipDraw = procedure(DC: HDC; const R: TRect; const Text: string; Measure: Boolean;
    MaxW: Integer; out W, H: Integer) of object;

  TNcTip = class
  private
    FOwner: HWND;
    FWin: TObject;
    FText: string;
    FRects: array of TRect;
    FBg, FFg, FBorder: Cardinal;
    FShown, FBlocked, FFixed: Boolean;
    FHoverStart, FShownAt: QWord;
    FHoverPt: TPoint;
    FOnDraw: TNcTipDraw;
    procedure Build;
    procedure Apply(const Txt: string);
    function CursorPos: TPoint;
    function InTool(const pt: TPoint): Boolean;
    procedure ShowAt(X, Y: Integer; Above: Boolean);
  public
    constructor Create(Owner: HWND);
    destructor Destroy; override;
    procedure SetRects(const R: array of TRect);   { client points of the owner; none = off }
    procedure SetText(const s: string);            { '' = never shows }
    procedure SetDpi(Dpi: Integer);
    procedure SetColors(Bg, Fg, Border: Cardinal);
    procedure Poll;
    procedure Hide;
    { shown at once, without hover tracking (a value readout while a control is dragged):
      centred under Anchor (screen points), or above it when there is no room below; Poll
      leaves it alone until Hide }
    procedure ShowFixed(const s: string; const Anchor: TRect);
    property Owner: HWND read FOwner;
    property Wnd: HWND read FOwner;
    property Shown: Boolean read FShown;
    property OnDraw: TNcTipDraw read FOnDraw write FOnDraw;
  end;

implementation

uses CocoaAll;

const
  PAD = 6;          { padding on every side (points) }
  BW = 1;           { border width }
  FONT_PT = 12;     { system font size (points) }
  MAXW = 420;       { wrap width of the text }
  CURSOR_DY = 18;   { tooltip top below the hot spot }

type
  TTipWin = class
    Panel: NSPanel;
    Box: NSBox;
    Lbl: NSTextField;
    TextW, TextH: Integer;
  end;

function NSCol(c: Cardinal): NSColor;
begin
  { COLORREF: $00BBGGRR }
  Result := NSColor.colorWithCalibratedRed_green_blue_alpha((c and $FF) / 255, ((c shr 8) and $FF) / 255,
    ((c shr 16) and $FF) / 255, 1);
end;

{ visible frame (Cocoa coordinates) of the screen that holds the LCL point (X, Y), y down from the
  top of the primary screen; falls back to the main screen }
function ScreenVisibleAt(X, Y: Integer): NSRect;
var
  i: Integer;
  scr: NSScreen;
  f: NSRect;
  cy, screenH: Double;
begin
  screenH := NSScreen.screens.objectAtIndex(0).frame.size.height;
  cy := screenH - Y;
  Result := NSScreen.mainScreen.visibleFrame;
  for i := 0 to Integer(NSScreen.screens.count) - 1 do
  begin
    scr := NSScreen(NSScreen.screens.objectAtIndex(i));
    f := scr.frame;
    if (X >= f.origin.x) and (X < f.origin.x + f.size.width) and
       (cy >= f.origin.y) and (cy <= f.origin.y + f.size.height) then
      Exit(scr.visibleFrame);
  end;
end;

constructor TNcTip.Create(Owner: HWND);
begin
  inherited Create;
  FOwner := Owner;
  FBg := $FFFFFF; FFg := 0; FBorder := $808080;
  Build;
end;

destructor TNcTip.Destroy;
var
  w: TTipWin;
begin
  w := TTipWin(FWin);
  if w <> nil then
  begin
    w.Panel.orderOut(nil);
    w.Panel.close;
    w.Lbl.release; w.Box.release;
    w.Free;
  end;
  inherited Destroy;
end;

procedure TNcTip.Build;
var
  w: TTipWin;
begin
  w := TTipWin.Create;
  FWin := w;
  w.Panel := NSPanel.alloc.initWithContentRect_styleMask_backing_defer(NSMakeRect(0, 0, 80, 24),
    NSBorderlessWindowMask or NSNonactivatingPanelMask, NSBackingStoreBuffered, True);
  w.Panel.setReleasedWhenClosed(False);
  w.Panel.setIgnoresMouseEvents(True);
  w.Panel.setHasShadow(True);
  w.Panel.setLevel(NSStatusWindowLevel);
  w.Panel.setOpaque(True);
  w.Panel.setHidesOnDeactivate(False);
  w.Panel.setBecomesKeyOnlyIfNeeded(True);
  w.Box := NSBox.alloc.initWithFrame(NSMakeRect(0, 0, 80, 24));
  w.Box.setBoxType(NSBoxCustom);
  w.Box.setTitlePosition(NSNoTitle);
  w.Box.setBorderType(NSLineBorder);
  w.Box.setBorderWidth(BW);
  w.Box.setCornerRadius(0);
  w.Box.setContentViewMargins(NSMakeSize(0, 0));
  w.Lbl := NSTextField.alloc.initWithFrame(NSMakeRect(PAD, PAD, 60, 12));
  w.Lbl.setBezeled(False);
  w.Lbl.setBordered(False);
  w.Lbl.setDrawsBackground(False);
  w.Lbl.setEditable(False);
  w.Lbl.setSelectable(False);
  w.Lbl.setFont(NSFont.systemFontOfSize(FONT_PT));
  w.Lbl.cell.setWraps(True);
  w.Box.contentView.addSubview(w.Lbl);
  w.Panel.setContentView(w.Box);
  Apply('');
end;

procedure TNcTip.Apply(const Txt: string);
var
  w: TTipWin;
  attrs: NSDictionary;
  r: NSRect;
  s: NSString;
begin
  w := TTipWin(FWin);
  w.Box.setFillColor(NSCol(FBg));
  w.Box.setBorderColor(NSCol(FBorder));
  w.Lbl.setTextColor(NSCol(FFg));
  s := NSString.stringWithUTF8String(PChar(Txt));   { UTF-8: Chinese titles must not turn into garbage }
  w.Lbl.setStringValue(s);
  attrs := NSDictionary.dictionaryWithObject_forKey(NSFont.systemFontOfSize(FONT_PT), NSFontAttributeName);
  r := s.boundingRectWithSize_options_attributes(NSMakeSize(MAXW, 10000),
    NSStringDrawingUsesLineFragmentOrigin or NSStringDrawingUsesFontLeading, attrs);
  w.TextW := Ceil(r.size.width) + 8;   { slack so the label never wraps / clips the last characters }
  w.TextH := Ceil(r.size.height) + 2;
  w.Lbl.setFrame(NSMakeRect(PAD + BW, PAD + BW, w.TextW, w.TextH));
  w.Panel.setContentSize(NSMakeSize(w.TextW + 2 * (PAD + BW), w.TextH + 2 * (PAD + BW)));
end;

procedure TNcTip.SetRects(const R: array of TRect);
var
  i: Integer;
begin
  SetLength(FRects, Length(R));
  for i := 0 to High(R) do FRects[i] := R[i];
  if Length(R) = 0 then Hide;
end;

procedure TNcTip.SetText(const s: string);
begin
  if s = FText then Exit;
  FText := s;
  if FShown and not FFixed then
  begin
    if s = '' then Hide else Apply(s);
  end;
end;

procedure TNcTip.SetDpi(Dpi: Integer);
begin
  { points are resolution independent }
end;

procedure TNcTip.SetColors(Bg, Fg, Border: Cardinal);
begin
  FBg := Bg; FFg := Fg; FBorder := Border;
  Apply(FText);
end;

function TNcTip.CursorPos: TPoint;
var
  p: NSPoint;
  screenH: Double;
begin
  p := NSEvent.mouseLocation;
  screenH := NSScreen.screens.objectAtIndex(0).frame.size.height;
  Result := Point(Round(p.x), Round(screenH - p.y));
end;

function TNcTip.InTool(const pt: TPoint): Boolean;
var
  v: NSView;
  win: NSWindow;
  p: NSPoint;
  r: NSRect;
  i: Integer;
  c: TPoint;
begin
  Result := False;
  if (Length(FRects) = 0) or (FText = '') or (FOwner = 0) then Exit;
  v := NSView(FOwner);
  win := v.window;
  if (win = nil) or not win.isVisible then Exit;
  { is the window under the cursor? }
  if NSWindow.windowNumberAtPoint_belowWindowWithWindowNumber(NSEvent.mouseLocation, 0) <> win.windowNumber then Exit;
  p := NSEvent.mouseLocation;
  r := win.convertRectFromScreen(NSMakeRect(p.x, p.y, 0, 0));
  p := v.convertPoint_fromView(r.origin, nil);
  if not v.isFlipped then p.y := v.bounds.size.height - p.y;
  c := Point(Round(p.x), Round(p.y));
  for i := 0 to High(FRects) do
    if PtInRect(FRects[i], c) then Exit(True);
end;

procedure TNcTip.ShowAt(X, Y: Integer; Above: Boolean);
var
  w: TTipWin;
  pw, ph: Integer;
  screenH: Double;
  vis: NSRect;
  ox, oy: Double;
begin
  w := TTipWin(FWin);
  pw := w.TextW + 2 * (PAD + BW);
  ph := w.TextH + 2 * (PAD + BW);
  screenH := NSScreen.screens.objectAtIndex(0).frame.size.height;
  vis := ScreenVisibleAt(X, Y);
  ox := X;
  if ox + pw > vis.origin.x + vis.size.width then ox := vis.origin.x + vis.size.width - pw;
  if ox < vis.origin.x then ox := vis.origin.x;
  { LCL (y down) -> Cocoa (y up): the window origin is its bottom-left }
  if Above then oy := screenH - Y else oy := screenH - Y - ph;
  if oy < vis.origin.y then oy := vis.origin.y;
  w.Panel.setFrameOrigin(NSMakePoint(ox, oy));
  w.Panel.orderFrontRegardless;
  FShown := True;
  FShownAt := GetTickCount64;
end;

procedure TNcTip.Poll;
var
  pt: TPoint;
  now: QWord;
  delay: QWord;
  w: TTipWin;
begin
  if (FOwner = 0) or FFixed then Exit;
  pt := CursorPos;
  now := GetTickCount64;
  if not InTool(pt) then
  begin
    Hide;
    FBlocked := False;
    FHoverStart := 0;
    Exit;
  end;
  if NSEvent.pressedMouseButtons <> 0 then
  begin
    Hide;                  { clicked / dragging: stay hidden until the mouse leaves }
    FBlocked := True;
    Exit;
  end;
  if FBlocked then Exit;
  delay := Round(NSEvent.doubleClickInterval * 1000);
  if delay < 200 then delay := 500;
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
    w := TTipWin(FWin);
    Apply(FText);
    ShowAt(pt.X, pt.Y + CURSOR_DY, False);
    if w = nil then Exit;
  end;
end;

procedure TNcTip.Hide;
begin
  if FShown and (FWin <> nil) then TTipWin(FWin).Panel.orderOut(nil);
  FShown := False;
  FFixed := False;
end;

procedure TNcTip.ShowFixed(const s: string; const Anchor: TRect);
var
  w: TTipWin;
  pw, ph, x, y: Integer;
  screenH: Double;
  vis: NSRect;
  oy: Double;
begin
  if (FWin = nil) or (s = '') then begin Hide; Exit; end;
  w := TTipWin(FWin);
  if (s <> FText) or not FFixed then begin FText := s; Apply(s); end;
  FFixed := True;
  pw := w.TextW + 2 * (PAD + BW);
  ph := w.TextH + 2 * (PAD + BW);
  x := (Anchor.Left + Anchor.Right - pw) div 2;
  y := Anchor.Bottom + 3;
  screenH := NSScreen.screens.objectAtIndex(0).frame.size.height;
  vis := ScreenVisibleAt(x, Anchor.Bottom);
  oy := screenH - y - ph;
  if oy < vis.origin.y then y := Anchor.Top - 3 - ph;   { flip above }
  ShowAt(x, y, False);
end;

end.
