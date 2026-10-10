{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit MainForm;
{ nc-amp - a compact, Winamp 2.x style player with a "Fusion"-like look.
  Everything is drawn with code in logical (classic 1x Winamp) units and
  scaled by the monitor DPI (per-monitor-v2 aware) times a user size factor. }
{$mode objfpc}{$H+}

interface

uses
  Windows, Messages, Classes, SysUtils, Math, Forms, Controls, Graphics,
  Dialogs, ExtCtrls, Menus, LCLType, LMessages, FileUtil, LazFileUtils, LazUTF8, IniFiles,
  NcAudio, TagReader, TitleFont, NcTray, SingleInst;

const
  APPNAME = 'nc-amp';
  APPTITLE = 'nc-amp';
  APPVERSION = '1.7.3';
  MAINW = 275;
  MAINH = 116;
  TITLEH = 16;        { ONE title-bar height for both windows (logical; scaled with identical rounding) }
  SHADE_EXTRA = 1.75; { shaded bar = title bar + 1.75 (2 px @96 DPI) so the title sits optically centred }
  SHADEH = TITLEH + SHADE_EXTRA;    { main window shaded height (logical) }
  PL_SHADEH = SHADEH; { playlist shaded: identical constant => identical pixels }
  PLT = TITLEH;       { playlist list frame starts flush under the title bar }
  PLW = 275;
  BASE_SCALE = 1.2;   { default UI is 20% larger than classic Winamp 2.x proportions }
  ROWH = 19;          { playlist row height (logical), ~1.45x the text }
  ROWTXT = 12.5;      { playlist text height (Latin em; CJK at 0.86x) }
  NBARS = 19;
  WM_NCAMP_APPLYDPI = WM_USER + 77;
  WM_NCAMP_IPC = WM_USER + 78;      { request forwarded by a second instance }
  AUDIO_MASK = '*.mp3;*.mp2;*.mp1;*.ogg;*.oga;*.opus;*.flac;*.fla;*.wav;*.aif;*.aiff;*.m4a;*.m4b;*.aac;*.mp4;*.wma';

type
  TBtnId = (bNone,
    { main window }
    bClose, bMin, bShade, bVisToggle,
    bPrev, bPlay, bPause, bStop, bNext, bEject, bPL,
    bSeek, bVol, bBal, bMove, bTime,
    { playlist window }
    bPLClose, bPLShade, bPLMove, bList, bScroll, bAddMenu, bSubFile,
    bNewList, bResize);

  TTrack = record
    Path: string;
    Title: string;
    Duration: Double;
    Scanned, Bad, Selected: Boolean;
    Id: Integer;
  end;

  TPlayState = (psStopped, psPlaying, psPaused);

  TPlaylistForm = class;

  { TMainForm }

  TMainForm = class(TForm)
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormPaint(Sender: TObject);
    procedure FormShow(Sender: TObject);
  private
    FBuf: TBitmap;
    FPL: TPlaylistForm;
    FTimer: TTimer;
    FTracks: array of TTrack;
    FCount, FNextId: Integer;
    FCur: Integer;
    FStream: Boolean;   { a track is open in the audio engine }
    FState: TPlayState;
    FVolume, FBalance: Integer;
    FShuffle, FRepeat, FShowPL, FVisOn, FShade, FPLShade: Boolean;
    FOrder: array of Integer;
    FOrderPos: Integer;
    FBars, FPeaks, FPeakVel: array[0..NBARS-1] of Single;
    FMarqueeOfs: Double;
    FPressed, FDragging, FHover: TBtnId;
    FSeekFrac: Double;
    FListTop, FFocus, FAnchor, FScanPos: Integer;
    FBitrate, FFreq, FChans, FFailStreak: Integer;
    FDiagTick: QWord;   { last audio-output diagnostics log }
    FOsdSlider: TBtnId; { bVol / bBal: value readout shown in the LCD title line }
    FOsdUntil: QWord;   { readout stays until this tick after release / wheel }
    FShowRemaining: Boolean;
    FStatusMsg: string;
    FDpiMain, FDpiPL: Integer;
    FScaleMain, FScalePL: Double;
    FPendMainDpi, FPendPLDpi: Integer;
    FPendRect: TRect;
    FPendHaveRect, FPendQueued: Boolean;
    FLastDpiCheck: QWord;
    FSizeMul: Double;
    FPLRows: Integer;
    FPLMatch: Boolean;        { playlist height locked to the main window height }
    FResizeStartH: Double;
    FMarqueeText: string;
    FMarqueeHold: Integer;
    { window moving / resizing }
    FMoveWin: TForm;
    FMoveStart, FWinStart: TPoint;
    FMoveDocked: Boolean;
    FResizeStartY, FResizeStartRows: Integer;
    procedure TimerTick(Sender: TObject);
    procedure LogEngine;
    function OsdText: string;
    procedure ShowOsd(id: TBtnId);
    procedure DiagOutput;
    procedure BuildMenus;
  private
    { no taskbar button: notification-area icon instead }
    FTray: TNcTray;
    FTrayTip: string;
    FDeactTick: QWord;
    FIpcPending: TStringList;
    FIpcRequests: Integer;
    procedure IpcRequest(Paths: TStrings);
    procedure HandleIpc;
    procedure AppDeactivate(Sender: TObject);
    procedure BuildTray;
    procedure TrayClick;
    procedure TrayMenu(X, Y: Integer);
    procedure TrayLog(const s: string);
    procedure ShowAddMenu;
    procedure UpdateTrayTip;
    procedure ShowApp;
    procedure HideApp;
    function AppVisibleAndActive: Boolean;
    procedure ShowMainMenu;
    procedure ApplyScale;
    function SM(v: Double): Integer;
    function SP(v: Double): Integer;
    procedure QueueDpi(FromPL: Boolean; NewDpi: Integer; Suggested: PRect);
    procedure ApplyPendingDpi(Data: PtrInt);
    procedure CheckDpi(const Why: string);
    function PLHeight: Double;
    procedure DrawMain(c: TCanvas);
    function HitMain(X, Y: Integer): TBtnId;
    function HitPL(X, Y: Integer): TBtnId;
    procedure DoButton(id: TBtnId);
    procedure UpdateSlider(id: TBtnId; X, Y: Integer);
    procedure StartMove(W: TForm);
    procedure DoMove;
    function IsDocked: Boolean;
    procedure SetSizeMul(M: Double);
    function AddPaths(const Paths: array of string): Integer;
    procedure AddOne(const fn: string);
    procedure BuildShuffle(First, AvoidFirst: Integer);
    procedure PlayIndex(i: Integer);
    procedure UserPlay(i: Integer);
    procedure NextTrack(Auto: Boolean);
    procedure PrevTrack;
    procedure StopPlay;
    procedure PlayPressed;
    procedure TogglePause;
    procedure SetShuffle(On: Boolean);
    procedure RemoveSelected;
    procedure ClearList;
    procedure AddFilesDialog;
    procedure AddDirDialog;
    procedure ApplyVolume;
    procedure SetPLVisible(V: Boolean);
    function VisibleRows: Integer;
    procedure EnsureVisible(i: Integer);
    function DisplayTitle(i: Integer): string;
    function CurPos: Double;
    function CurLen: Double;
    function ConfigDir: string;
    procedure SaveState;
    procedure LoadState;
    procedure InvalidateAll;
    procedure ShowInfo;
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure SetHover(id: TBtnId);
    procedure WndProc(var TheMessage: TLMessage); override;
  public
    procedure EraseBackground(DC: HDC); override;
    procedure OnDrop(Sender: TObject; const FileNames: array of string);
    procedure HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure HandleWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    procedure DrawPlaylist(c: TCanvas; H: Integer);
    procedure PLMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure PLMouseMove(Shift: TShiftState; X, Y: Integer);
    procedure PLMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
  end;

  { TPlaylistForm - separate, independently movable window }

  TPlaylistForm = class(TForm)
  private
    FOwnerMain: TMainForm;
    FBuf: TBitmap;
    procedure PaintIt(Sender: TObject);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure WndProc(var TheMessage: TLMessage); override;
  public
    constructor CreatePL(AMain: TMainForm);
    destructor Destroy; override;
    procedure EraseBackground(DC: HDC); override;
  end;

var
  Form1: TMainForm;

implementation

{$R *.lfm}

{ ===================== scaling + drawing helpers ===================== }

var
  G: Double = 1.0;            { current pixel scale: monitor DPI / 96 * size factor }
  FontUI, FontSmall, FontLCD, FontLat: string;

function P(v: Double): Integer; inline;
begin
  Result := Round(v * G);
end;

function LR(x, y, w, h: Double): TRect;
begin
  Result := Rect(P(x), P(y), P(x + w), P(y + h));
end;

function LW: Integer; inline;
begin
  Result := Max(1, Round(G));
end;

function InL(X, Y: Integer; lx, ly, lw_, lh: Double): Boolean;
var
  fx, fy: Double;
begin
  fx := X / G; fy := Y / G;
  Result := (fx >= lx) and (fx < lx + lw_) and (fy >= ly) and (fy < ly + lh);
end;

function RGB_(r, g, b: Integer): TColor; inline;
begin
  Result := TColor(r or (g shl 8) or (b shl 16));
end;

function Blend(c1, c2: TColor; t: Double): TColor;
begin
  if t < 0 then t := 0;
  if t > 1 then t := 1;
  Result := RGB_(Round((c1 and $FF) + ((c2 and $FF) - (c1 and $FF)) * t),
                 Round(((c1 shr 8) and $FF) + (((c2 shr 8) and $FF) - ((c1 shr 8) and $FF)) * t),
                 Round(((c1 shr 16) and $FF) + (((c2 shr 16) and $FF) - ((c1 shr 16) and $FF)) * t));
end;

var
  { palette sampled from the reference "Fusion" skin screenshot }
  cBody, cBody2, cPanel, cPanelLt, cEdgeLt, cEdgeDk, cBezel, cSage, cSageDk,
  cSageDot, cInk, cInkSoft, cInkGhost, cYellow, cSel, cChromeLt, cChromeMid, cChromeDk,
  cLabel, cTitleTop, cTitleBot: TColor;

procedure InitColors;
begin
  cBody := RGB_(38, 38, 38);
  cBody2 := RGB_(49, 49, 49);
  cPanel := RGB_(60, 64, 64);
  cPanelLt := RGB_(87, 87, 87);
  cEdgeLt := RGB_(157, 157, 157);
  cEdgeDk := RGB_(11, 11, 11);
  cBezel := RGB_(8, 9, 9);
  cSage := RGB_(192, 216, 184);
  cSageDk := RGB_(169, 189, 164);
  cSageDot := RGB_(176, 198, 168);
  cInk := RGB_(78, 82, 87);
  cInkSoft := RGB_(98, 108, 104);
  cInkGhost := RGB_(181, 204, 173);
  cYellow := RGB_(244, 248, 31);
  cSel := RGB_(146, 168, 138);
  cChromeLt := RGB_(232, 233, 236);
  cChromeMid := RGB_(186, 190, 197);
  cChromeDk := RGB_(110, 112, 116);
  cLabel := RGB_(164, 164, 163);
  cTitleTop := RGB_(104, 105, 105);
  cTitleBot := RGB_(58, 58, 58);
end;

function PickFont(const Names: array of string): string;
var
  i: Integer;
begin
  for i := 0 to High(Names) do
    if Screen.Fonts.IndexOf(Names[i]) >= 0 then Exit(Names[i]);
  Result := 'Tahoma';
end;

function AddFontMemResourceEx(pbFont: Pointer; cbFont: DWORD; pdv: Pointer;
  pcFonts: PDWORD): THandle; stdcall; external 'gdi32.dll';

{ load the embedded LCD font privately; returns its GDI face name or '' }
function LoadLcdFont: string;
var
  rs: THandle; hg: HGLOBAL; n: DWORD; f: HFONT; dc: HDC; old: HGDIOBJ;
  face: array[0..63] of WideChar;
  cand: array[0..1] of UnicodeString = ('IBM Plex Mono Medium', 'IBM Plex Mono');
  i: Integer;
begin
  Result := '';
  rs := FindResourceW(HInstance, 'LCDFONT', PWideChar(RT_RCDATA));
  if rs = 0 then Exit;
  hg := LoadResource(HInstance, rs);
  n := 0;
  if (hg = 0) or (AddFontMemResourceEx(LockResource(hg), SizeofResource(HInstance, rs), nil, @n) = 0) then Exit;
  dc := GetDC(0);
  try
    for i := 0 to High(cand) do
    begin
      f := CreateFontW(-20, 0, 0, 0, FW_NORMAL, 0, 0, 0, DEFAULT_CHARSET, 0, 0, 0, 0, PWideChar(cand[i]));
      old := SelectObject(dc, f);
      FillChar(face, SizeOf(face), 0);
      GetTextFaceW(dc, 63, @face[0]);
      SelectObject(dc, old); DeleteObject(f);
      if WideCompareText(UnicodeString(PWideChar(@face[0])), cand[i]) = 0 then
        Exit(UTF8Encode(cand[i]));
    end;
  finally
    ReleaseDC(0, dc);
  end;
end;

procedure FillC(c: TCanvas; const r: TRect; col: TColor);
begin
  c.Brush.Style := bsSolid;
  c.Brush.Color := col;
  c.FillRect(r);
end;

procedure GradV(c: TCanvas; const r: TRect; c1, c2: TColor);
var
  y, h: Integer;
begin
  h := r.Bottom - r.Top;
  if h <= 0 then Exit;
  c.Brush.Style := bsSolid;
  for y := r.Top to r.Bottom - 1 do
  begin
    c.Brush.Color := Blend(c1, c2, (y - r.Top) / Max(1, h - 1));
    c.FillRect(Rect(r.Left, y, r.Right, y + 1));
  end;
end;

{ 3D frame of thickness LW: lt on top/left, dk on bottom/right }
procedure Frame3(c: TCanvas; const r: TRect; lt, dk: TColor);
var
  t: Integer;
begin
  t := LW;
  FillC(c, Rect(r.Left, r.Top, r.Right, r.Top + t), lt);
  FillC(c, Rect(r.Left, r.Top, r.Left + t, r.Bottom), lt);
  FillC(c, Rect(r.Left, r.Bottom - t, r.Right, r.Bottom), dk);
  FillC(c, Rect(r.Right - t, r.Top, r.Right, r.Bottom), dk);
end;

{ recessed panel: dark outer line top/left, light bottom/right }
procedure Recess(c: TCanvas; const r: TRect; fill: TColor);
begin
  FillC(c, r, fill);
  Frame3(c, r, RGB_(20, 20, 20), RGB_(96, 96, 96));
end;

procedure GradRound(c: TCanvas; const r: TRect; rad: Integer; c1, c2, edge: TColor);
var
  rgn: HRGN;
begin
  rgn := CreateRoundRectRgn(r.Left, r.Top, r.Right + 1, r.Bottom + 1, rad, rad);
  SelectClipRgn(c.Handle, rgn);
  GradV(c, r, c1, c2);
  SelectClipRgn(c.Handle, 0);
  DeleteObject(rgn);
  c.Brush.Style := bsClear;
  c.Pen.Color := edge;
  c.Pen.Width := 1;
  c.RoundRect(r.Left, r.Top, r.Right, r.Bottom, rad, rad);
  c.Brush.Style := bsSolid;
end;

procedure SetF(c: TCanvas; const Face: string; hLogical: Double; Bold: Boolean; Col: TColor);
begin
  c.Font.Name := Face;
  c.Font.Height := -Max(6, Round(hLogical * G));
  if Bold then c.Font.Style := [fsBold] else c.Font.Style := [];
  c.Font.Color := Col;
  c.Font.Quality := fqDefault;
  c.Brush.Style := bsClear;
end;

procedure TextAtC(c: TCanvas; const r: TRect; const s: string);
begin
  c.Brush.Style := bsClear;
  c.TextOut((r.Left + r.Right - c.TextWidth(s)) div 2, (r.Top + r.Bottom - c.TextHeight(s)) div 2, s);
end;

{ letter-spaced, embossed logo text; returns right edge }
{ ---- LCD text: Latin runs in the embedded IBM Plex Mono Medium font, everything else
  (CJK etc.) in Microsoft YaHei UI, on a common baseline ---- }
const
  { sizes are given as a nominal LCD text height h: YaHei UI is drawn at
    0.875h, Plex Mono at 0.92h so its x-height matches YaHei's Latin x-height }
  CJK_SCALE = 0.875;
  LAT_SCALE = 0.92;

function IsLatinCP(cp: Cardinal): Boolean;
begin
  Result := (cp < $250) or ((cp >= $2010) and (cp <= $2027)) or (cp = $2122);
end;

procedure SetLcdFont(c: TCanvas; Latin: Boolean; hLogical: Double);
begin
  if Latin then
  begin
    c.Font.Name := FontLat;
    c.Font.Height := -Max(6, Round(hLogical * LAT_SCALE * G));
  end
  else
  begin
    c.Font.Name := FontUI;
    c.Font.Height := -Max(6, Round(hLogical * CJK_SCALE * G));
  end;
  c.Font.Style := [];
  c.Font.Quality := fqDefault;
end;

type
  TRun = record s: string; Latin: Boolean; end;
  TRuns = array of TRun;

function SplitRuns(const s: string): TRuns;
var
  i, n, L: Integer; cp: Cardinal; lat: Boolean; ch: string;
begin
  Result := nil;
  i := 1;
  while i <= Length(s) do
  begin
    ch := UTF8Copy(Copy(s, i, 4), 1, 1);
    L := Length(ch); if L = 0 then begin L := 1; ch := s[i]; end;
    cp := UTF8CodepointToUnicode(PChar(ch), n);
    lat := IsLatinCP(cp);
    { spaces always use the mono font, so ' - ' separators are symmetric }
    if (Length(Result) = 0) or (Result[High(Result)].Latin <> lat) then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)].Latin := lat;
      Result[High(Result)].s := '';
    end;
    Result[High(Result)].s := Result[High(Result)].s + ch;
    Inc(i, L);
  end;
end;

function LcdAscent(c: TCanvas): Integer;
var
  tm: Windows.TTextMetric;
begin
  Windows.GetTextMetrics(c.Handle, tm);
  Result := tm.tmAscent;
end;

function LcdWidth(c: TCanvas; const s: string; hLogical: Double): Integer;
var
  r: TRuns; i: Integer;
begin
  Result := 0;
  r := SplitRuns(s);
  for i := 0 to High(r) do
  begin
    SetLcdFont(c, r[i].Latin, hLogical);
    Inc(Result, c.TextWidth(r[i].s));
  end;
end;

{ height of a line in device px (for vertical centring) and the baseline offset }
procedure LcdMetrics(c: TCanvas; hLogical: Double; out LineH, Base: Integer);
var
  tm: Windows.TTextMetric; aL, dL, aC, dC: Integer;
begin
  SetLcdFont(c, True, hLogical); Windows.GetTextMetrics(c.Handle, tm);
  aL := tm.tmAscent - tm.tmInternalLeading div 2; dL := tm.tmDescent;
  SetLcdFont(c, False, hLogical); Windows.GetTextMetrics(c.Handle, tm);
  aC := tm.tmAscent - tm.tmInternalLeading div 2; dC := tm.tmDescent;
  Base := Max(aL, aC);
  LineH := Base + Max(dL, dC);
end;

{ draw s clipped to clip, starting at x, with the baseline at y }
function LcdOut(c: TCanvas; const clip: TRect; x, baseY: Integer; const s: string;
  hLogical: Double; col: TColor): Integer;
var
  r: TRuns; i: Integer;
begin
  r := SplitRuns(s);
  c.Brush.Style := bsClear;
  for i := 0 to High(r) do
  begin
    SetLcdFont(c, r[i].Latin, hLogical);
    c.Font.Color := col;
    c.TextRect(clip, x, baseY - LcdAscent(c), r[i].s);
    Inc(x, c.TextWidth(r[i].s));
  end;
  Result := x;
end;

{ vertically centred in r }
procedure LcdInRect(c: TCanvas; const r: TRect; x: Integer; const s: string; hLogical: Double; col: TColor);
var
  lh, b: Integer;
  tm: Windows.TTextMetric;
begin
  if (Length(SplitRuns(s)) = 1) and SplitRuns(s)[0].Latin then
  begin
    { Latin only: centre the cap height }
    SetLcdFont(c, True, hLogical);
    Windows.GetTextMetrics(c.Handle, tm);
    lh := tm.tmAscent - tm.tmInternalLeading; b := lh;
  end
  else
    LcdMetrics(c, hLogical, lh, b);
  LcdOut(c, r, x, r.Top + (r.Bottom - r.Top - lh + 1) div 2 + b, s, hLogical, col);
end;

function SpacedText(c: TCanvas; x, y: Integer; const s: string; spacing: Integer;
  Col, Shadow, Hilite: TColor): Integer;
var
  i: Integer;
  ch: string;
begin
  c.Brush.Style := bsClear;
  for i := 1 to Length(s) do
  begin
    ch := s[i];
    if ch = ' ' then
    begin
      Inc(x, c.TextWidth('I') + spacing);
      Continue;
    end;
    c.Font.Color := Shadow; c.TextOut(x + LW, y + LW, ch);
    c.Font.Color := Hilite; c.TextOut(x, y - 1, ch);
    c.Font.Color := Col; c.TextOut(x, y, ch);
    Inc(x, c.TextWidth(ch) + spacing);
  end;
  Result := x - spacing;
end;

const
  { title bars: optical centre of the inner bar (below the 2-line top edge),
    baseline = centre + x-height/2, minus a little for the drop shadow }
  TB_MAIN_CY = 9.33;  TB_MAIN_BASE = 12.2;    { main bar 0..16 }
  TB_PL_CY = TB_MAIN_CY; TB_PL_BASE = TB_MAIN_BASE; { playlist bar: identical 0..16 }
  { shade bar layout (logical units): title 10..~68, transport, time, seek, window buttons 235.. }
  SH_BTN_X = 76;  SH_BTN_P = 12;            { 5 cells 76..136 }
  SH_TIME_X = 142; SH_TIME_W = 34;          { 142..176 }
  SH_SEEK_X = 182; SH_SEEK_W = 56;          { 182..238 (room freed by the removed minimise button) }
  PL_BOT = 19;        { playlist bottom bar height (incl. bottom edge) }
  MQ_HOLD = 30;   { marquee pause at the start of each loop (logical px of travel) }
  MQ_H = 10;                       { marquee text height (logical) }
  TBW = 42.4;                      { transport button width (logical) }
  TITLE_FACE = TColor($E3E0DE);    { RGB(222,224,227) white print }
  TITLE_SHADOW = TColor($121212);  { crisp drop shadow }

function TitleShadowOff: Integer;
begin
  Result := Max(1, Round(G / 1.5));
end;

function SpacedWidth(c: TCanvas; const s: string; spacing: Integer): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(s) do
    if s[i] = ' ' then Inc(Result, c.TextWidth('I') + spacing)
    else Inc(Result, c.TextWidth(s[i]) + spacing);
  Dec(Result, spacing);
end;

procedure Tri(c: TCanvas; x1, y1, x2, y2, x3, y3: Integer; col: TColor);
var
  pts: array[0..2] of TPoint;
begin
  pts[0] := Point(x1, y1); pts[1] := Point(x2, y2); pts[2] := Point(x3, y3);
  c.Brush.Style := bsSolid;
  c.Brush.Color := col;
  c.Pen.Color := col;
  c.Pen.Width := 1;
  c.Polygon(pts);
end;

{ small transport glyph centred in r (pixels) }
procedure Glyph(c: TCanvas; id: TBtnId; const r: TRect; col: TColor; sz: Double);
var
  cx, cy, s, b: Integer;
begin
  cx := (r.Left + r.Right) div 2;
  cy := (r.Top + r.Bottom) div 2;
  s := Max(2, Round(sz * G));
  b := Max(1, Round(sz * G * 0.35));
  c.Brush.Style := bsSolid;
  c.Brush.Color := col;
  case id of
    bPlay: Tri(c, cx - s div 2, cy - s, cx + s - s div 2, cy, cx - s div 2, cy + s, col);
    bPause:
      begin
        c.FillRect(Rect(cx - s, cy - s, cx - s + b + 1, cy + s + 1));
        c.FillRect(Rect(cx + s - b, cy - s, cx + s + 1, cy + s + 1));
      end;
    bStop: c.FillRect(Rect(cx - s + 1, cy - s + 1, cx + s, cy + s));
    bPrev:
      begin
        c.FillRect(Rect(cx - s, cy - s, cx - s + b + 1, cy + s + 1));
        Tri(c, cx + s, cy - s, cx - s + b + 1, cy, cx + s, cy + s, col);
      end;
    bNext:
      begin
        c.FillRect(Rect(cx + s - b, cy - s, cx + s + 1, cy + s + 1));
        Tri(c, cx - s, cy - s, cx + s - b - 1, cy, cx - s, cy + s, col);
      end;
    bEject:
      begin
        Tri(c, cx - s, cy + b div 2, cx, cy - s, cx + s, cy + b div 2, col);
        c.FillRect(Rect(cx - s, cy + b div 2 + Max(1, b div 2) + 1, cx + s + 1, cy + s + 1));
      end;
  end;
end;

const
  SegMap: array[0..9] of Byte = ($3F, $06, $5B, $4F, $66, $6D, $7D, $07, $7F, $6F);

{ 7-segment digit in logical units }
procedure DrawDigitL(c: TCanvas; lx, ly, lw_, lh, lt: Double; mask: Byte; OnCol, OffCol: TColor);
var
  x, y, w, h, t, hm: Integer;
  procedure Seg(bit: Integer; x1, y1, x2, y2: Integer);
  begin
    if (mask and (1 shl bit)) <> 0 then c.Brush.Color := OnCol else c.Brush.Color := OffCol;
    c.FillRect(Rect(x1, y1, x2, y2));
  end;
begin
  x := P(lx); y := P(ly); w := P(lw_); h := P(lh);
  t := Max(1, Round(lt * G));
  c.Brush.Style := bsSolid;
  hm := y + (h - t) div 2;
  Seg(0, x + t, y, x + w - t, y + t);
  Seg(1, x + w - t, y + t, x + w, hm);
  Seg(2, x + w - t, hm + t, x + w, y + h - t);
  Seg(3, x + t, y + h - t, x + w - t, y + h);
  Seg(4, x, hm + t, x + t, y + h - t);
  Seg(5, x, y + t, x + t, hm);
  Seg(6, x + t, hm, x + w - t, hm + t);
end;

function FmtTime(sec: Double): string;
var
  t: Integer;
begin
  if sec < 0 then Exit('');
  t := Trunc(sec);
  if t >= 3600 then
    Result := Format('%d:%.2d:%.2d', [t div 3600, (t div 60) mod 60, t mod 60])
  else
    Result := Format('%d:%.2d', [t div 60, t mod 60]);
end;

{ optional diagnostics: set environment variable NCAMP_LOG=<file> }
procedure DebugLog(const msg: string);
var
  fn: string;
  f: TextFile;
begin
  fn := GetEnvironmentVariable('NCAMP_LOG');
  if fn = '' then Exit;
  try
    AssignFile(f, fn);
    if FileExists(fn) then Append(f) else Rewrite(f);
    WriteLn(f, FormatDateTime('hh:nn:ss.zzz', Now), ' ', msg);
    CloseFile(f);
  except
  end;
end;

type
  TGetDpiForWindow = function(h: HWND): UINT; stdcall;
  TGetDpiForMonitor = function(hmon: HMONITOR; dpiType: Integer; out dpiX, dpiY: UINT): HRESULT; stdcall;
var
  pGetDpiForWindow: TGetDpiForWindow = nil;
  pGetDpiForMonitor: TGetDpiForMonitor = nil;
  DpiApisLoaded: Boolean = False;

function MonitorFromWindow(h: HWND; flags: DWORD): HMONITOR; stdcall; external 'user32.dll';
function MonitorFromPoint(pt: TPoint; flags: DWORD): HMONITOR; stdcall; external 'user32.dll';

const
  MONITOR_DEFAULTTONEAREST = 2;

procedure LoadDpiApis;
var
  h: HMODULE;
begin
  if DpiApisLoaded then Exit;
  DpiApisLoaded := True;
  Pointer(pGetDpiForWindow) := GetProcAddress(GetModuleHandle('user32.dll'), 'GetDpiForWindow');
  h := LoadLibrary('shcore.dll');
  if h <> 0 then Pointer(pGetDpiForMonitor) := GetProcAddress(h, 'GetDpiForMonitor');
end;

function SystemDpi: Integer;
var
  dc: HDC;
begin
  dc := GetDC(0);
  Result := GetDeviceCaps(dc, LOGPIXELSY);
  ReleaseDC(0, dc);
  if Result <= 0 then Result := 96;
end;

function MonitorDpi(hmon: HMONITOR): Integer;
var
  dx, dy: UINT;
begin
  Result := 0;
  LoadDpiApis;
  if (hmon <> 0) and Assigned(pGetDpiForMonitor) then
    if pGetDpiForMonitor(hmon, 0 {MDT_EFFECTIVE_DPI}, dx, dy) = S_OK then Result := dy;
  if Result <= 0 then Result := SystemDpi;
end;

{ DPI of the monitor a window is on: GetDpiForWindow -> GetDpiForMonitor -> system DPI }
function WindowDpi(h: HWND): Integer;
begin
  Result := 0;
  LoadDpiApis;
  if (h <> 0) and Assigned(pGetDpiForWindow) then Result := pGetDpiForWindow(h);
  if Result <= 0 then Result := MonitorDpi(MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST));
end;

function DpiAtPoint(const pt: TPoint): Integer;
begin
  Result := MonitorDpi(MonitorFromPoint(pt, MONITOR_DEFAULTTONEAREST));
end;

function AwarenessName: string;
type
  TGetAwareCtx = function: THandle; stdcall;
  TGetAwareFromCtx = function(ctx: THandle): Integer; stdcall;
var
  f1: TGetAwareCtx;
  f2: TGetAwareFromCtx;
  a: Integer;
begin
  Result := 'unknown';
  Pointer(f1) := GetProcAddress(GetModuleHandle('user32.dll'), 'GetThreadDpiAwarenessContext');
  Pointer(f2) := GetProcAddress(GetModuleHandle('user32.dll'), 'GetAwarenessFromDpiAwarenessContext');
  if Assigned(f1) and Assigned(f2) then
  begin
    a := f2(f1());
    case a of
      0: Result := 'unaware';
      1: Result := 'system-aware';
      2: Result := 'per-monitor-aware';
    else Result := IntToStr(a);
    end;
  end;
end;

{ ===================== TPlaylistForm ===================== }

constructor TPlaylistForm.CreatePL(AMain: TMainForm);
begin
  inherited CreateNew(AMain);
  FOwnerMain := AMain;
  BorderStyle := bsNone;
  Caption := APPNAME + ' playlist';
  ShowInTaskBar := stNever;
  KeyPreview := True;
  Position := poDesigned;
  Color := RGB_(49, 49, 49);
  FBuf := TBitmap.Create;
  FBuf.PixelFormat := pf24bit;
  OnPaint := @PaintIt;
  OnKeyDown := @AMain.HandleKey;
  OnMouseWheel := @AMain.HandleWheel;
  AllowDropFiles := True;
  OnDropFiles := @AMain.OnDrop;
end;

destructor TPlaylistForm.Destroy;
begin
  FBuf.Free;
  inherited Destroy;
end;

procedure TPlaylistForm.EraseBackground(DC: HDC);
begin
end;

procedure TPlaylistForm.PaintIt(Sender: TObject);
begin
  if (FBuf.Width <> ClientWidth) or (FBuf.Height <> ClientHeight) then
    FBuf.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  G := FOwnerMain.FScalePL;
  FOwnerMain.DrawPlaylist(FBuf.Canvas, Round(ClientHeight / G));
  Canvas.Draw(0, 0, FBuf);
end;

procedure TPlaylistForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  G := FOwnerMain.FScalePL;
  FOwnerMain.PLMouseDown(Button, Shift, X, Y);
end;

procedure TPlaylistForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  G := FOwnerMain.FScalePL;
  FOwnerMain.PLMouseMove(Shift, X, Y);
end;

procedure TPlaylistForm.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  G := FOwnerMain.FScalePL;
  FOwnerMain.PLMouseUp(Button, Shift, X, Y);
end;

procedure TPlaylistForm.WndProc(var TheMessage: TLMessage);
begin
  if TheMessage.Msg = LM_DPICHANGED then
  begin
    FOwnerMain.QueueDpi(True, HiWord(TheMessage.WParam), nil);
    TheMessage.Result := 0;
    Exit;
  end;
  inherited WndProc(TheMessage);
  if TheMessage.Msg = WM_GETMINMAXINFO then
    with PMinMaxInfo(TheMessage.LParam)^ do ptMinTrackSize := Classes.Point(1, 1);
end;

{ ===================== TMainForm: setup / scaling ===================== }

procedure TMainForm.FormCreate(Sender: TObject);
var
  i: Integer;
  args: array of string;
begin
  Randomize;
  FShuffle := True;   { permanent: shuffle every round, then reshuffle }
  FRepeat := True;
  InitColors;
  FontUI := PickFont(['Microsoft YaHei UI', 'Microsoft YaHei', 'Noto Sans CJK SC', 'SimHei', 'Segoe UI', 'Tahoma']);
  FontSmall := PickFont(['Tahoma', 'Arial', 'Segoe UI']);
  FontLCD := PickFont(['Lucida Console', 'Consolas', 'Courier New']);
  FontLat := LoadLcdFont;
  if FontLat = '' then FontLat := PickFont(['Segoe UI', 'Tahoma']);
  BorderStyle := bsNone;
  Caption := APPNAME;
  ShowInTaskBar := stNever;   { no taskbar button: owned by the hidden app window; tray icon instead }
  Color := cBody;
  KeyPreview := True;
  OnKeyDown := @HandleKey;
  OnMouseWheel := @HandleWheel;
  AllowDropFiles := True;
  OnDropFiles := @OnDrop;
  Position := poDesigned;
  FBuf := TBitmap.Create;
  FBuf.PixelFormat := pf24bit;
  FCur := -1; FFocus := -1; FAnchor := -1; FOrderPos := -1;
  FVolume := 80; FBalance := 0;
  FShowPL := True; FVisOn := True;
  FSizeMul := 1.0;
  FPLRows := 24;
  FDpiMain := 96; FDpiPL := 96;
  FScaleMain := 1; FScalePL := 1;
  Left := -32000;   { real position is set in FormShow, once the DPI is known }

  { a missing output device is not fatal: the engine keeps retrying and follows the
    default endpoint (see nca_poll) }
  if not LoadAudio then
    FStatusMsg := 'AUDIO ENGINE ERROR: ' + AudioError;
  DebugLog('audio engine loaded=' + BoolToStr(AudioLoaded, True) + ' device=' + BoolToStr(AudioReady, True) +
    ' ' + AudioVersion + ' ' + AudioError);
  LogEngine;

  FPL := TPlaylistForm.CreatePL(Self);
  BuildMenus;
  BuildTray;
  FIpcPending := TStringList.Create;
  StartIpcServer(@IpcRequest);   { second instances forward their files here }
  LoadState;

  SetLength(args, 0);
  for i := 1 to ParamCount do
  begin
    SetLength(args, Length(args) + 1);
    args[High(args)] := ParamStr(i);
  end;
  if Length(args) > 0 then OnDrop(nil, args);

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 25;
  FTimer.OnTimer := @TimerTick;
  FTimer.Enabled := True;
end;

var
  SavedMainPos, SavedPLPos: TPoint;
  HaveSavedPos: Boolean = False;
  ShownOnce: Boolean = False;

function TMainForm.SM(v: Double): Integer;
begin
  Result := Round(v * FScaleMain);
end;

function TMainForm.SP(v: Double): Integer;
begin
  Result := Round(v * FScalePL);
end;

procedure TMainForm.FormShow(Sender: TObject);
var
  st: PtrInt;
  wa: TRect;
  ok: Boolean;
begin
  if ShownOnce then Exit;
  ShownOnce := True;
  st := GetWindowLongPtr(Handle, GWL_STYLE);
  SetWindowLongPtr(Handle, GWL_STYLE, st or WS_MINIMIZEBOX or WS_SYSMENU);
  ok := HaveSavedPos and (SavedMainPos.X > Screen.DesktopLeft - 100) and
     (SavedMainPos.X < Screen.DesktopLeft + Screen.DesktopWidth - 50) and
     (SavedMainPos.Y > Screen.DesktopTop - 20) and
     (SavedMainPos.Y < Screen.DesktopTop + Screen.DesktopHeight - 30);
  if ok then
  begin
    { DPI of the monitor(s) the saved positions land on }
    FDpiMain := DpiAtPoint(Point(SavedMainPos.X + 20, SavedMainPos.Y + 10));
    FDpiPL := DpiAtPoint(Point(SavedPLPos.X + 20, SavedPLPos.Y + 10));
    FScaleMain := FDpiMain / 96 * BASE_SCALE * FSizeMul;
    FScalePL := FDpiPL / 96 * BASE_SCALE * FSizeMul;
    SetBounds(SavedMainPos.X, SavedMainPos.Y, SM(MAINW), SM(MAINH));
    FPL.SetBounds(SavedPLPos.X, SavedPLPos.Y, SP(PLW), SP(PLHeight));
  end
  else
  begin
    wa := Screen.MonitorFromPoint(Mouse.CursorPos).WorkareaRect;
    FDpiMain := DpiAtPoint(Point((wa.Left + wa.Right) div 2, (wa.Top + wa.Bottom) div 2));
    FDpiPL := FDpiMain;
    FScaleMain := FDpiMain / 96 * BASE_SCALE * FSizeMul;
    FScalePL := FScaleMain;
    Left := wa.Left + (wa.Right - wa.Left - 2 * SM(MAINW)) div 2;
    Top := wa.Top + (wa.Bottom - wa.Top - SP(PLHeight)) div 3;
    if Top < wa.Top then Top := wa.Top;
    FPL.SetBounds(Left + SM(MAINW), Top, SP(PLW), SP(PLHeight));
  end;
  ApplyScale;
  DebugLog(Format('startup: awareness=%s system-dpi=%d dpi(main)=%d dpi(pl)=%d size=%.2f main=%dx%d@%d,%d pl=%dx%d@%d,%d',
    [AwarenessName, SystemDpi, FDpiMain, FDpiPL, FSizeMul, Width, Height, Left, Top,
     FPL.Width, FPL.Height, FPL.Left, FPL.Top]));
  if FShowPL then FPL.Show;
  { re-check once both windows really exist on screen }
  CheckDpi('after show');
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  StopIpcServer;
  FreeAndNil(FIpcPending);
  FreeAndNil(FTray);
  SaveState;
  if FTimer <> nil then FTimer.Enabled := False;
  if AudioLoaded then nca_close();
  UnloadAudio;
  FBuf.Free;
end;

procedure TMainForm.EraseBackground(DC: HDC);
begin
end;

procedure TMainForm.FormPaint(Sender: TObject);
begin
  if (FBuf.Width <> ClientWidth) or (FBuf.Height <> ClientHeight) then
    FBuf.SetSize(Max(1, ClientWidth), Max(1, ClientHeight));
  G := FScaleMain;
  DrawMain(FBuf.Canvas);
  Canvas.Draw(0, 0, FBuf);
end;

procedure TMainForm.InvalidateAll;
begin
  Invalidate;
  if (FPL <> nil) and FPL.Visible then FPL.Invalidate;
end;

function TMainForm.PLHeight: Double;
begin
  if FPLShade then Result := PL_SHADEH
  else if FPLMatch then Result := MAINH   { same logical base + same scale => identical pixels }
  else Result := PLT + 4 + 2 + FPLRows * ROWH + PL_BOT;   { title, frame, list, bottom bar }
end;

{ 0 = not docked, 1 = playlist right of main, 2 = below, 3 = left, 4 = above }
function DockSideOf(const m, p: TRect): Integer;
begin
  Result := 0;
  if (Abs(p.Left - m.Right) <= 2) and (p.Top < m.Bottom) and (p.Bottom > m.Top) then Exit(1);
  if (Abs(p.Top - m.Bottom) <= 2) and (p.Left < m.Right) and (p.Right > m.Left) then Exit(2);
  if (Abs(p.Right - m.Left) <= 2) and (p.Top < m.Bottom) and (p.Bottom > m.Top) then Exit(3);
  if (Abs(p.Bottom - m.Top) <= 2) and (p.Left < m.Right) and (p.Right > m.Left) then Exit(4);
end;

function TMainForm.IsDocked: Boolean;
begin
  Result := FPL.Visible and (DockSideOf(BoundsRect, FPL.BoundsRect) <> 0);
end;

{ Resize both windows for their current DPI and the size factor; keep the
  playlist docked if it was docked. }
procedure TMainForm.ApplyScale;
var
  side, offs: Integer;
  oldS: Double;
begin
  side := DockSideOf(BoundsRect, FPL.BoundsRect);
  if not FPL.Visible and ShownOnce then side := 0;
  oldS := FScaleMain;
  if side in [1, 3] then offs := FPL.Top - Top else offs := FPL.Left - Left;
  FScaleMain := FDpiMain / 96 * BASE_SCALE * FSizeMul;
  if side <> 0 then
  begin
    FDpiPL := FDpiMain;      { a docked playlist always follows the main window }
    if oldS > 0 then offs := Round(offs * FScaleMain / oldS);
    if FPLMatch and (side in [1, 3]) then offs := 0;   { locked: same top, same height }
  end;
  FScalePL := FDpiPL / 96 * BASE_SCALE * FSizeMul;
  if FShade then SetBounds(Left, Top, SM(MAINW), SM(SHADEH))
  else SetBounds(Left, Top, SM(MAINW), SM(MAINH));
  case side of
    1: FPL.SetBounds(Left + Width, Top + offs, SP(PLW), SP(PLHeight));
    2: FPL.SetBounds(Left + offs, Top + Height, SP(PLW), SP(PLHeight));
    3: FPL.SetBounds(Left - SP(PLW), Top + offs, SP(PLW), SP(PLHeight));
    4: FPL.SetBounds(Left + offs, Top - SP(PLHeight), SP(PLW), SP(PLHeight));
  else
    FPL.SetBounds(FPL.Left, FPL.Top, SP(PLW), SP(PLHeight));
  end;
  InvalidateAll;
end;

{ WM_DPICHANGED arrives while LCL is still inside its own SetBounds/UpdateBounds
  for the move (BoundsLockCount > 0), so resizing synchronously gets overwritten.
  We remember it and apply it asynchronously, after the move has been processed. }
procedure TMainForm.QueueDpi(FromPL: Boolean; NewDpi: Integer; Suggested: PRect);
begin
  DebugLog(Format('WM_DPICHANGED (%s): new dpi=%d', [BoolToStr(FromPL, 'playlist', 'main'), NewDpi]));
  if FromPL then FPendPLDpi := NewDpi
  else
  begin
    FPendMainDpi := NewDpi;
    FPendHaveRect := (Suggested <> nil) and (FMoveWin = nil);
    if FPendHaveRect then
    begin
      FPendRect := Suggested^;
      { ignore an implausible rect instead of throwing the window off-screen }
      if (Abs(FPendRect.Left) > 100000) or (Abs(FPendRect.Top) > 100000) or
         (FPendRect.Right <= FPendRect.Left) or (FPendRect.Bottom <= FPendRect.Top) then
        FPendHaveRect := False;
    end;
  end;
  if not FPendQueued then
  begin
    FPendQueued := True;
    PostMessage(Handle, WM_NCAMP_APPLYDPI, 0, 0);
  end;
end;

procedure TMainForm.ApplyPendingDpi(Data: PtrInt);
var
  didChange: Boolean;
begin
  FPendQueued := False;
  didChange := False;
  if (FPendMainDpi > 0) and (FPendMainDpi <> FDpiMain) then
  begin
    if FPendHaveRect then
    begin
      if IsDocked then
        FPL.SetBounds(FPL.Left + FPendRect.Left - Left, FPL.Top + FPendRect.Top - Top, FPL.Width, FPL.Height);
      SetBounds(FPendRect.Left, FPendRect.Top, Width, Height);
    end;
    FDpiMain := FPendMainDpi;
    didChange := True;
  end;
  if (FPendPLDpi > 0) and (FPendPLDpi <> FDpiPL) and not IsDocked then
  begin
    FDpiPL := FPendPLDpi;
    didChange := True;
  end;
  FPendMainDpi := 0; FPendPLDpi := 0; FPendHaveRect := False;
  if didChange then
  begin
    ApplyScale;
    DebugLog(Format('dpi applied: main=%d pl=%d scale=%.3f/%.3f main=%dx%d pl=%dx%d',
      [FDpiMain, FDpiPL, FScaleMain, FScalePL, Width, Height, FPL.Width, FPL.Height]));
  end;
end;

{ safety net: poll the real per-window DPI (also covers cases where the
  message was not delivered) }
procedure TMainForm.CheckDpi(const Why: string);
var
  dm, dp: Integer;
begin
  if not ShownOnce or not HandleAllocated then Exit;
  dm := WindowDpi(Handle);
  if FPL.Visible and FPL.HandleAllocated then dp := WindowDpi(FPL.Handle) else dp := FDpiPL;
  if (dm <> FDpiMain) or ((dp <> FDpiPL) and not IsDocked) then
  begin
    DebugLog(Format('dpi check (%s): main %d->%d pl %d->%d', [Why, FDpiMain, dm, FDpiPL, dp]));
    FDpiMain := dm;
    if not IsDocked then FDpiPL := dp;
    ApplyScale;
  end;
end;

procedure TMainForm.WndProc(var TheMessage: TLMessage);
begin
  if TheMessage.Msg = LM_DPICHANGED then
  begin
    QueueDpi(False, HiWord(TheMessage.WParam), PRect(TheMessage.LParam));
    TheMessage.Result := 0;
    Exit;
  end;
  if TheMessage.Msg = WM_NCAMP_IPC then
  begin
    HandleIpc;
    TheMessage.Result := 0;
    Exit;
  end;
  if TheMessage.Msg = WM_NCAMP_APPLYDPI then
  begin
    ApplyPendingDpi(0);
    TheMessage.Result := 0;
    Exit;
  end;
  inherited WndProc(TheMessage);
  { never let Windows clamp our custom sizes (e.g. the thin shade bar) to a
    minimum tracking size }
  if TheMessage.Msg = WM_GETMINMAXINFO then
    with PMinMaxInfo(TheMessage.LParam)^ do ptMinTrackSize := Classes.Point(1, 1);
end;

procedure TMainForm.SetSizeMul(M: Double);
begin
  FSizeMul := M;
  ApplyScale;
end;

procedure TMainForm.SetPLVisible(V: Boolean);
begin
  FShowPL := V;
  if ShownOnce then
  begin
    if V then FPL.Show
    else FPL.Hide;
  end;
  InvalidateAll;
end;

{ ---------- menus ---------- }

procedure TMainForm.BuildMenus;
begin
  { all popup menus are native Win32 menus built on demand (see NativePopup):
    drawn by Windows with the system menu font, per-monitor DPI correct }
end;

type
  TNMItem = record
    Cap: string;
    Id: Integer;
    Checked, Def: Boolean;
  end;

function NM(const Cap: string; Id: Integer; Checked: Boolean = False; Def: Boolean = False): TNMItem;
begin
  Result.Cap := Cap; Result.Id := Id; Result.Checked := Checked; Result.Def := Def;
end;

{ Plain Win32 popup menu: no owner-draw, no custom font. Returns the chosen id or 0. }
function NativePopup(Owner: HWND; const Items: array of TNMItem; FromTray: Boolean; AtX: Integer = MaxInt; AtY: Integer = MaxInt): Integer;
var
  hm: HMENU;
  i: Integer;
  fl: UINT;
  pt: TPoint;
  w: UnicodeString;
  oldCtx: THandle;
  tp: TTPMParams;
begin
  Result := 0;
  hm := CreatePopupMenu;
  if hm = 0 then Exit;
  try
    for i := 0 to High(Items) do
      if Items[i].Cap = '-' then
        AppendMenuW(hm, MF_SEPARATOR, 0, nil)
      else
      begin
        fl := MF_STRING;
        if Items[i].Checked then fl := fl or MF_CHECKED;
        w := UTF8Decode(Items[i].Cap);
        AppendMenuW(hm, fl, Items[i].Id, PWideChar(w));
      end;
    if AtX = MaxInt then GetCursorPos(pt) else begin pt.X := AtX; pt.Y := AtY; end;
    { required for notification-area menus so they close when clicking elsewhere }
    if FromTray then SetForegroundWindow(Owner);
    { menus are laid out for the owner's DPI with the thread's DPI context: force PMv2 }
    oldCtx := BeginPMv2;
    DebugLog(Format('popup: tray=%s owner dpi=%d thread=%s at %d,%d',
      [BoolToStr(FromTray, True), WindowDpi(Owner), ThreadAwarenessName, pt.X, pt.Y]));
    { never cover the click point (the tray icon) }
    tp.cbSize := SizeOf(tp);
    tp.rcExclude := Rect(pt.X - 1, pt.Y - 1, pt.X + 1, pt.Y + 1);
    Result := Integer(TrackPopupMenuEx(hm, TPM_RETURNCMD or TPM_RIGHTBUTTON or TPM_NONOTIFY or TPM_VERTICAL,
      pt.X, pt.Y, Owner, @tp));
    EndPMv2(oldCtx);
    if FromTray then PostMessage(Owner, WM_NULL, 0, 0);
  finally
    DestroyMenu(hm);
  end;
end;

procedure TMainForm.ShowMainMenu;
var
  id: Integer;
begin
  id := NativePopup(Handle, [
    NM('Size 1x (follows Windows display scaling)', 1, SameValue(FSizeMul, 1.0)),
    NM('Size 1.5x', 2, SameValue(FSizeMul, 1.5)),
    NM('Size 2x', 3, SameValue(FSizeMul, 2.0)),
    NM('-', 0),
    NM('Playlist window', 11, FShowPL),
    NM('Visualization', 12, FVisOn),
    NM('-', 0),
    NM('Add files...', 20),
    NM('Add folder...', 21),
    NM('-', 0),
    NM('File info / about...', 40),
    NM('Exit', 99)], False);
  DebugLog('main menu -> ' + IntToStr(id));
  case id of
    1: SetSizeMul(1.0);
    2: SetSizeMul(1.5);
    3: SetSizeMul(2.0);
    11: SetPLVisible(not FShowPL);
    12: begin FVisOn := not FVisOn; InvalidateAll; end;
    20: AddFilesDialog;
    21: AddDirDialog;
    40: ShowInfo;
    99: Close;
  end;
end;

procedure TMainForm.ShowAddMenu;
var
  id: Integer;
begin
  id := NativePopup(FPL.Handle, [NM('Add files...', 20), NM('Add folder (with sub-folders)...', 21)], False);
  DebugLog('add menu -> ' + IntToStr(id));
  case id of
    20: AddFilesDialog;
    21: AddDirDialog;
  end;
end;

procedure TMainForm.ShowInfo;
var
  s: string;
begin
  s := APPNAME + ' ' + APPVERSION + ' - classic style music player'#13#10 +
    'Copyright (C) 2026 Shen Min - GPL-3.0-or-later'#13#10 +
    'https://github.com/shenmin/nc-amp'#13#10#13#10 +
    'Audio: ' + AudioVersion + #13#10 +
    'Fonts: Audiowide (title), IBM Plex Mono (LCD) - SIL OFL 1.1' + #13#10 +
    Format('Display: %d DPI, size %.1fx, scale %.2f', [FDpiMain, FSizeMul, FScaleMain]) + #13#10#13#10;
  if FCur >= 0 then
  begin
    s := s + 'Now: ' + DisplayTitle(FCur) + #13#10 + FTracks[FCur].Path + #13#10;
    if FState <> psStopped then
      s := s + Format('%d kbps, %d Hz, %d ch, %s', [FBitrate, FFreq, FChans, FmtTime(CurLen)]);
  end
  else
    s := s + 'Drop music files or folders on the window to play them (shuffled, looping).';
  { native message box: system message font, DPI-scaled by Windows }
  MessageBoxW(Handle, PWideChar(UTF8Decode(s)), PWideChar(UTF8Decode(APPNAME)), MB_OK or MB_ICONINFORMATION);
end;

{ ===================== drawing: main window ===================== }

procedure DarkPill(c: TCanvas; const r: TRect);
begin
  GradRound(c, r, r.Bottom - r.Top, RGB_(74, 75, 76), RGB_(26, 26, 26), RGB_(150, 151, 152));
end;

procedure ChromePill(c: TCanvas; const r: TRect; Pressed: Boolean);
begin
  if Pressed then
    GradRound(c, r, Max(2, (r.Bottom - r.Top) * 2 div 3), RGB_(120, 122, 126), RGB_(190, 192, 196), RGB_(30, 30, 30))
  else
    GradRound(c, r, Max(2, (r.Bottom - r.Top) * 2 div 3), cChromeLt, RGB_(140, 142, 147), RGB_(30, 30, 30));
end;

procedure ChromeThumb(c: TCanvas; const r: TRect; Pressed: Boolean);
var
  cx, i: Integer;
begin
  if Pressed then GradRound(c, r, P(2), RGB_(150, 152, 156), RGB_(220, 222, 226), RGB_(28, 28, 28))
  else GradRound(c, r, P(2), cChromeLt, RGB_(120, 122, 126), RGB_(28, 28, 28));
  cx := (r.Left + r.Right) div 2;
  for i := -1 to 1 do
    if i <> 0 then
      FillC(c, Rect(cx + i * P(1.5), r.Top + P(2.5), cx + i * P(1.5) + LW, r.Bottom - P(2.5)), RGB_(70, 72, 76));
end;

{ title-bar buttons: three equal 9-unit cells (min / shade / close) with
  2-unit gaps, right edge at x = 266 (aligned with the content below);
  glyphs are 6 units wide, anti-aliased, centred on cy }
const
  CELL_MIN = 239.5; CELL_SHADE = 250.5; CELL_CLOSE = 261.5;

procedure WinGlyphs(c: TCanvas; cy: Double; WithMin: Boolean; PressedId: TBtnId; IdMin, IdShade, IdClose: TBtnId; Shaded: Boolean = False);
var
  col: TColor;
  x, y, a, hw, th: Double;
  function GC(id: TBtnId): TColor;
  begin
    if PressedId = id then Result := clWhite else Result := RGB_(176, 177, 178);
  end;
  function SX(v: Double): Double; begin Result := Round(v * G * 2) / 2; end;
begin
  y := SX(cy);
  hw := 3 * G; th := 1.75 * G;
  if WithMin then
  begin
    x := SX(CELL_MIN);
    FillPolysAA(c, [x - hw, y - th, x + hw, y - th, x, y + th], [3], GC(IdMin));
  end;
  x := SX(CELL_SHADE);
  if Shaded then   { shaded: inverted triangle = expand }
    FillPolysAA(c, [x - hw, y - th, x + hw, y - th, x, y + th], [3], GC(IdShade))
  else             { unshaded: up triangle = collapse }
    FillPolysAA(c, [x - hw, y + th, x + hw, y + th, x, y - th], [3], GC(IdShade));
  { close: X from two strokes, same 6-unit footprint, fine line }
  x := SX(CELL_CLOSE);
  a := 2.75 * G;
  col := GC(IdClose);
  hw := Max(0.55, 0.62 * G) / Sqrt(2);   { half stroke along the normal }
  FillPolysAA(c, [
    x - a - hw, y - a + hw, x + a - hw, y + a + hw, x + a + hw, y + a - hw, x - a + hw, y - a - hw,
    x - a + hw, y + a + hw, x + a + hw, y - a + hw, x + a - hw, y - a - hw, x - a - hw, y + a - hw],
    [4, 4], col);
end;

procedure WindowFrame(c: TCanvas; w, h: Double; Top1, Top2, Bot1, Bot2: TColor; TitleH: Double);
var
  r: TRect;
begin
  GradV(c, LR(0, 0, w, TitleH), Top1, Top2);
  GradV(c, Rect(0, P(TitleH), P(w), P(h)), Bot1, Bot2);
  r := Rect(0, 0, P(w), P(h));
  Frame3(c, r, RGB_(130, 131, 131), RGB_(12, 12, 12));
  InflateRect(r, -LW, -LW);
  Frame3(c, r, RGB_(92, 92, 92), RGB_(36, 36, 36));
end;

{ a shaded window is just the title bar: identical gradient and top/left/right
  edges as the unshaded title bar (so the title pixels do not change), closed
  by the outer dark bottom edge }
procedure ShadeFrame(c: TCanvas; w, h: Double; Top1, Top2: TColor);
var
  r: TRect;
begin
  { gradient exactly as the unshaded title bar (0..TITLEH), then continue its end colour }
  GradV(c, LR(0, 0, w, TITLEH), Top1, Top2);
  FillC(c, Rect(0, P(TITLEH), P(w), P(h)), Top2);
  r := Rect(LW, LW, P(w) - LW, P(h) + LW);
  Frame3(c, r, RGB_(92, 92, 92), RGB_(36, 36, 36));
  r := Rect(0, 0, P(w), P(h));
  Frame3(c, r, RGB_(130, 131, 131), RGB_(12, 12, 12));
end;

{ shade-mode transport glyphs, 6 units, centred on (cx, cy) }
procedure ShadeGlyph(c: TCanvas; id: TBtnId; cx, cy: Double; col: TColor);
  function X(v: Double): Double; begin Result := Round(cx * G * 2) / 2 + v * G; end;
  function Y(v: Double): Double; begin Result := Round(cy * G * 2) / 2 + v * G; end;
begin
  case id of
    bPlay:  FillPolysAA(c, [X(-2.4), Y(-3), X(3), Y(0), X(-2.4), Y(3)], [3], col);
    bPause: FillPolysAA(c, [X(-2.6), Y(-3), X(-0.8), Y(-3), X(-0.8), Y(3), X(-2.6), Y(3),
                            X(0.8), Y(-3), X(2.6), Y(-3), X(2.6), Y(3), X(0.8), Y(3)], [4, 4], col);
    bStop:  FillPolysAA(c, [X(-2.6), Y(-2.6), X(2.6), Y(-2.6), X(2.6), Y(2.6), X(-2.6), Y(2.6)], [4], col);
    bPrev:  FillPolysAA(c, [X(-3), Y(-3), X(-1.6), Y(-3), X(-1.6), Y(3), X(-3), Y(3),
                            X(3), Y(-3), X(3), Y(3), X(-1.6), Y(0)], [4, 3], col);
    bNext:  FillPolysAA(c, [X(-3), Y(-3), X(1.6), Y(0), X(-3), Y(3),
                            X(1.6), Y(-3), X(3), Y(-3), X(3), Y(3), X(1.6), Y(3)], [3, 4], col);
  end;
end;

procedure TMainForm.DrawMain(c: TCanvas);
var
  r: TRect;
  i, j, k, x, y, tw, th, mins, secs, d: Integer;
  t, len, frac, cyc, sz: Double;
  sepw: Integer;
  s, mq, osd: string;
  col: TColor;
  blink: Boolean;
const
  ids: array[0..4] of TBtnId = (bPrev, bPlay, bPause, bStop, bNext);
  labels: array[0..4] of string = ('PREV', 'PLAY', 'PAUSE', 'STOP', 'NEXT');
begin
  if FShade then
  begin
    { exactly the title bar: same gradient, same title size/position }
    ShadeFrame(c, MAINW, SHADEH, cTitleTop, RGB_(72, 72, 72));
    DrawTitle(c, P(10), Round(TB_MAIN_BASE * G), 6.33 * G, 1.67 * G, TITLE_FACE, TITLE_SHADOW, TitleShadowOff);
    { transport: prev play pause stop next, 11-unit cells on a 12 pitch }
    for i := 0 to 4 do
    begin
      r := LR(SH_BTN_X + i * SH_BTN_P, TB_MAIN_CY - 5.5, SH_BTN_P - 1, 11);
      if FPressed = ids[i] then
      begin
        c.Brush.Color := RGB_(38, 39, 41); c.Pen.Color := RGB_(30, 30, 31);
        c.RoundRect(r.Left, r.Top, r.Right, r.Bottom, P(3), P(3));
      end
      else if FHover = ids[i] then
      begin
        c.Brush.Color := RGB_(100, 102, 105); c.Pen.Color := RGB_(118, 120, 123);
        c.RoundRect(r.Left, r.Top, r.Right, r.Bottom, P(3), P(3));
      end;
      if FPressed = ids[i] then col := clWhite
      else if ((ids[i] = bPlay) and (FState = psPlaying)) or ((ids[i] = bPause) and (FState = psPaused)) then
        col := RGB_(200, 236, 186)                 { lit = current state }
      else if FHover = ids[i] then col := RGB_(236, 237, 238)
      else col := RGB_(176, 177, 178);
      ShadeGlyph(c, ids[i], SH_BTN_X + i * SH_BTN_P + (SH_BTN_P - 1) / 2, TB_MAIN_CY, col);
    end;
    { elapsed time (click = elapsed / remaining) }
    r := LR(SH_TIME_X, TB_MAIN_CY - 5, SH_TIME_W, 10);
    FillC(c, r, cSage);
    Frame3(c, r, RGB_(24, 24, 24), RGB_(110, 112, 112));
    if FState <> psStopped then
    begin
      t := CurPos;
      if FShowRemaining and (CurLen > 0) then s := '-' + FmtTime(Max(0, CurLen - t)) else s := FmtTime(t);
      col := cInk;
    end
    else begin s := '0:00'; col := cInkSoft; end;
    LcdInRect(c, r, (r.Left + r.Right - LcdWidth(c, s, 8)) div 2, s, 8, col);
    { seek strip }
    FillC(c, LR(SH_SEEK_X, TB_MAIN_CY - 1.2, SH_SEEK_W, 2.4), cBezel);
    FillC(c, Rect(P(SH_SEEK_X), P(TB_MAIN_CY + 1.2), P(SH_SEEK_X + SH_SEEK_W), P(TB_MAIN_CY + 1.2) + LW), RGB_(100, 100, 100));
    len := CurLen;
    if FStream and (len > 0) then
    begin
      if FDragging = bSeek then frac := FSeekFrac else frac := Min(1, CurPos / len);
      x := Round((SH_SEEK_X + (SH_SEEK_W - 8) * frac) * G);
      ChromeThumb(c, Rect(x, P(TB_MAIN_CY - 3.5), x + P(8), P(TB_MAIN_CY + 3.5)), FDragging = bSeek);
    end;
    WinGlyphs(c, TB_MAIN_CY, False, FPressed, bNone, bShade, bClose, True);
    Exit;
  end;

  WindowFrame(c, MAINW, MAINH, cTitleTop, RGB_(72, 72, 72), RGB_(56, 58, 58), RGB_(33, 33, 33), TITLEH);
  DrawTitle(c, P(10), Round(TB_MAIN_BASE * G), 6.33 * G, 1.67 * G, TITLE_FACE, TITLE_SHADOW, TitleShadowOff);
  WinGlyphs(c, TB_MAIN_CY, False, FPressed, bNone, bShade, bClose);

  { LCD: state, time (click = elapsed/remaining), spectrum (click = on/off) }
  GradRound(c, LR(10, 20, 86, 47), P(4), RGB_(16, 16, 16), RGB_(8, 8, 8), RGB_(70, 70, 70));
  GradV(c, LR(12, 61, 82, 5), RGB_(24, 24, 24), RGB_(86, 86, 88));
  FillC(c, LR(13, 23, 80, 37), cSage);
  FillC(c, LR(13, 23, 80, 0.7), cSageDk);
  case FState of
    psPlaying: Tri(c, P(17), P(27), P(22.5), P(30), P(17), P(33), cInk);
    psPaused:
      begin
        FillC(c, LR(17, 27, 1.8, 6), cInk);
        FillC(c, LR(20.2, 27, 1.8, 6), cInk);
      end;
  else
    FillC(c, LR(17, 27.5, 5, 5), cInk);
  end;
  t := CurPos;
  len := CurLen;
  if FDragging = bSeek then t := FSeekFrac * len;
  if FShowRemaining and (len > 0) then t := Max(0, len - t);
  k := Trunc(t);
  mins := (k div 60) mod 100; secs := k mod 60;
  blink := (FState = psPaused) and (((GetTickCount64 div 500) mod 2) = 0);
  if FShowRemaining and (FState <> psStopped) then FillC(c, LR(30, 30.8, 5, 1.4), cInk);
  for j := 0 to 3 do
  begin
    case j of
      0: d := mins div 10;
      1: d := mins mod 10;
      2: d := secs div 10;
    else d := secs mod 10;
    end;
    if j < 2 then x := 39 + j * 9 else x := 66 + (j - 2) * 9;
    if (FState = psStopped) or blink then
      DrawDigitL(c, x, 27, 6, 9, 1.3, 0, cInk, cInkGhost)
    else
      DrawDigitL(c, x, 27, 6, 9, 1.3, SegMap[d], cInk, cInkGhost);
  end;
  FillC(c, LR(61.2, 29, 1.4, 1.4), cInk);
  FillC(c, LR(61.2, 32.8, 1.4, 1.4), cInk);
  k := Max(1, Round(G * 0.75));
  for i := 0 to 38 do
    for j := 0 to 9 do
      FillC(c, Rect(P(14.5 + i * 2), P(40.5 + j * 2), P(14.5 + i * 2) + k, P(40.5 + j * 2) + k), cSageDot);
  if FVisOn then
    for i := 0 to NBARS - 1 do
    begin
      x := P(15 + i * 4);
      k := Round(FBars[i] * 19);
      for j := 0 to k - 1 do
      begin
        col := Blend(RGB_(98, 124, 92), RGB_(46, 50, 54), j / 18);
        FillC(c, Rect(x, P(59 - j - 1), P(15 + i * 4 + 3), P(59 - j)), col);
      end;
      k := Round(FPeaks[i] * 19);
      if k > 0 then FillC(c, Rect(x, P(59 - k - 1), P(15 + i * 4 + 3), P(59 - k - 1) + LW), RGB_(40, 42, 44));
    end;

  { title panel: scrolling "NN. Artist - Title (m:ss)", bitrate, sample rate, channels }
  r := LR(100, 22, 166, 30);
  FillC(c, r, cSage);
  Frame3(c, r, RGB_(24, 24, 24), RGB_(110, 112, 112));
  osd := OsdText;
  if FStatusMsg <> '' then mq := FStatusMsg
  else if FCur >= 0 then
  begin
    mq := Format('%d. %s', [FCur + 1, DisplayTitle(FCur)]);
    if FTracks[FCur].Duration > 0 then mq := mq + ' (' + FmtTime(FTracks[FCur].Duration) + ')';
  end
  else if FCount = 1 then mq := APPNAME + ' - 1 track'
  else if FCount > 0 then mq := APPNAME + ' - ' + IntToStr(FCount) + ' tracks'
  else mq := APPNAME + ' - drop music here';
  if mq <> FMarqueeText then
  begin
    FMarqueeText := mq;     { new text: start from its beginning }
    FMarqueeOfs := 0;
  end;
  r := LR(103, 23, 160, 13);
  if osd <> '' then mq := osd;     { volume / balance readout: static, marquee state kept }
  tw := LcdWidth(c, mq, MQ_H);
  LcdMetrics(c, MQ_H, th, k);
  y := r.Top + (r.Bottom - r.Top - th) div 2 + k;
  if (osd <> '') or (tw <= r.Right - r.Left) then
    LcdOut(c, r, r.Left, y, mq, MQ_H, cInk)
  else
  begin
    { scroll: pause at the start, then text + separator + text, seamless loop }
    sepw := LcdWidth(c, '   ***   ', MQ_H);
    cyc := (tw + sepw) / G + MQ_HOLD;
    t := FMarqueeOfs - Floor(FMarqueeOfs / cyc) * cyc;
    k := Round(Max(0, t - MQ_HOLD) * G);
    x := LcdOut(c, r, r.Left - k, y, mq, MQ_H, cInk);
    x := LcdOut(c, r, x, y, '   ***   ', MQ_H, cInk);
    LcdOut(c, r, x, y, mq, MQ_H, cInk);
  end;
  { bitrate / sample rate / channels, on one baseline }
  y := P(49);
  r := LR(100, 36, 166, 16);
  LcdOut(c, r, P(123), y, 'kbps', 6.6, cInkSoft);
  LcdOut(c, r, P(164), y, 'kHz', 6.6, cInkSoft);
  if FState <> psStopped then
  begin
    { plain average kbps, up to 4 digits (e.g. 1411); 4-digit values get a slightly
      narrower size so they stay inside the LCD field at every DPI }
    s := IntToStr(EnsureRange(FBitrate, 0, 9999));
    sz := 9;
    while (LcdWidth(c, s, sz) > P(121) - P(104)) and (sz > 6) do sz := sz - 0.25;
    LcdOut(c, r, P(121) - LcdWidth(c, s, sz), y, s, sz, cInk);
    s := IntToStr(Round(FFreq / 1000));
    if (FFreq mod 1000) <> 0 then s := FormatFloat('0.#', FFreq / 1000);
    LcdOut(c, r, P(162) - LcdWidth(c, s, 9), y, s, 9, cInk);
    if FChans = 1 then s := 'mono' else if FChans = 2 then s := 'stereo' else s := IntToStr(FChans) + ' ch';
    LcdOut(c, r, P(262) - LcdWidth(c, s, 6.6), y, s, 6.6, cInkSoft);
  end;

  { volume / balance }
  r := LR(100, 56, 138, 13);
  FillC(c, r, RGB_(36, 37, 37));
  Frame3(c, r, RGB_(22, 22, 22), RGB_(96, 96, 96));
  FillC(c, LR(104, 61, 74, 2.4), cBezel);
  FillC(c, Rect(P(104), P(63.4), P(178), P(63.4) + LW), RGB_(100, 100, 100));
  x := Round((104 + 60 * FVolume / 100) * G);
  ChromeThumb(c, Rect(x, P(58), x + P(14), P(66)), FDragging = bVol);
  FillC(c, LR(184, 61, 50, 2.4), cBezel);
  FillC(c, Rect(P(184), P(63.4), P(234), P(63.4) + LW), RGB_(100, 100, 100));
  FillC(c, LR(208.5, 59.5, 1, 1.2), RGB_(110, 110, 110));
  x := Round((184 + 36 * (FBalance + 100) / 200) * G);
  ChromeThumb(c, Rect(x, P(58), x + P(14), P(66)), FDragging = bBal);
  { PL toggle }
  DarkPill(c, LR(243, 57.5, 23, 10));
  SetF(c, FontSmall, 6.5, True, RGB_(150, 150, 150));
  if FShowPL then c.Font.Color := RGB_(232, 232, 232);
  if FPressed = bPL then c.Font.Color := clWhite;
  TextAtC(c, LR(243, 57.5, 23, 10), 'PL');

  { seek bar }
  FillC(c, LR(12, 74.5, 254, 2.4), cBezel);
  FillC(c, Rect(P(12), P(76.9), P(266), P(76.9) + LW), RGB_(96, 96, 96));
  len := CurLen;
  if FStream and (len > 0) then
  begin
    if FDragging = bSeek then frac := FSeekFrac else frac := Min(1, CurPos / len);
    x := Round((12 + 226 * frac) * G);
    ChromeThumb(c, Rect(x, P(71.5), x + P(28), P(80)), FDragging = bSeek);
  end;

  { transport }
  r := LR(9, 82, 224, 25);
  FillC(c, r, RGB_(50, 52, 52));
  Frame3(c, r, RGB_(108, 108, 108), RGB_(18, 18, 18));
  SetF(c, FontSmall, 6, False, RGB_(160, 160, 160));
  for i := 0 to 4 do
    TextAtC(c, LR(15 + i * TBW, 84, TBW, 8), labels[i]);
  ChromePill(c, LR(15, 93, 5 * TBW, 11), False);
  for i := 0 to 4 do
  begin
    r := LR(15 + i * TBW, 93, TBW, 11);
    if FPressed = ids[i] then
      GradV(c, Rect(r.Left + LW, r.Top + LW, r.Right - LW, r.Bottom - LW), RGB_(112, 114, 118), RGB_(176, 178, 182));
    if i > 0 then FillC(c, Rect(r.Left, r.Top + LW, r.Left + LW, r.Bottom - LW), RGB_(84, 86, 90));
    Glyph(c, ids[i], r, RGB_(40, 41, 44), 2.4);
  end;
  { open files (eject), aligned with the PL button column }
  DarkPill(c, LR(243, 91, 23, 15));
  r := LR(247.5, 94.5, 14, 8);
  ChromePill(c, r, FPressed = bEject);
  Glyph(c, bEject, r, RGB_(40, 41, 44), 2.2);
end;

{ ===================== drawing: playlist window ===================== }

function TMainForm.VisibleRows: Integer;
begin
  { full rows that fit; a locked (main-height) playlist may show a partial row }
  if FPLShade then Result := FPLRows
  else Result := Max(1, (Round(PLHeight) - PLT - 4 - 2 - PL_BOT) div ROWH);
end;

procedure TMainForm.DrawPlaylist(c: TCanvas; H: Integer);
var
  r, rr, full: TRect;
  i, y, vis, tw, th, x, k, n: Integer;
  col: TColor;
  s, d: string;
  total: Double;
  unknown: Boolean;
  BarCY, LH, t1, t2, o1, o2: Double;
  procedure Btn(lx, lw_: Double; const cap: string; id: TBtnId);
  begin
    if FPressed = id then c.Font.Color := clWhite else c.Font.Color := cLabel;
    TextAtC(c, LR(lx, BarCY - 6.5, lw_, 13), cap);
  end;
begin
  if FPLShade then
  begin
    { just the title bar: same gradient, title and buttons as unshaded }
    ShadeFrame(c, PLW, PL_SHADEH, RGB_(96, 96, 96), RGB_(60, 60, 60));
    tw := TitleWidth(6.33 * G, 1.67 * G);
    DrawTitle(c, P(10), Round(TB_PL_BASE * G), 6.33 * G, 1.67 * G, TITLE_FACE, TITLE_SHADOW, TitleShadowOff);
    WinGlyphs(c, TB_PL_CY, False, FPressed, bNone, bPLShade, bPLClose, True);
    Exit;
  end;
  WindowFrame(c, PLW, H, RGB_(96, 96, 96), RGB_(60, 60, 60), cBody2, RGB_(45, 45, 45), TITLEH);
  LH := H - PLT - 4 - PL_BOT;                       { sage list height }
  BarCY := H - PL_BOT + (PL_BOT - 1.33) / 2;       { centre of the bottom bar }
  tw := TitleWidth(6.33 * G, 1.67 * G);
  DrawTitle(c, P(10), Round(TB_PL_BASE * G), 6.33 * G, 1.67 * G, TITLE_FACE, TITLE_SHADOW, TitleShadowOff);
  WinGlyphs(c, TB_PL_CY, False, FPressed, bNone, bPLShade, bPLClose);

  { list }
  { list frame inset 7 left/right, flush under the title bar, bottom bar below }
  r := LR(7, PLT, 261, LH + 4);
  FillC(c, r, RGB_(16, 16, 16));
  Frame3(c, r, RGB_(14, 14, 14), RGB_(100, 100, 100));
  FillC(c, LR(9, PLT + 2, 257, LH), cSage);
  vis := VisibleRows;
  if FListTop > Max(0, FCount - vis) then FListTop := Max(0, FCount - vis);
  if FListTop < 0 then FListTop := 0;
  LcdMetrics(c, ROWTXT, th, k);
  for i := FListTop to Min(FCount - 1, FListTop + vis) do
  begin
    y := P(PLT + 3 + (i - FListTop) * ROWH);
    if y >= P(PLT + 2 + LH) then Break;
    { a row cut by the bottom of the list is laid out at its full height (so the
      text keeps its normal position) and clipped to the frame; a sliver showing
      less than 60% of the row is left empty instead of showing glyph fragments }
    full := Rect(P(9), y, P(266), P(PLT + 3 + (i - FListTop + 1) * ROWH));
    r := full;
    if r.Bottom > P(PLT + 2 + LH) then
    begin
      r.Bottom := P(PLT + 2 + LH);
      if (r.Bottom - r.Top) < 0.6 * (full.Bottom - full.Top) then Break;
    end;
    if FTracks[i].Selected then FillC(c, r, cSel);
    if i = FCur then col := cYellow
    else if FTracks[i].Bad then col := RGB_(150, 70, 60)
    else col := cInk;
    s := Format('%3d. %s', [i + 1, DisplayTitle(i)]);   { fixed 3-digit column (mono font) }
    d := FmtTime(FTracks[i].Duration);
    tw := LcdWidth(c, d, ROWTXT);
    rr := Rect(P(14), r.Top, P(253) - tw - P(10), r.Bottom);
    if LcdWidth(c, s, ROWTXT) > rr.Right - rr.Left then
    begin
      while (Length(s) > 1) and (LcdWidth(c, s + '...', ROWTXT) > rr.Right - rr.Left) do
      begin
        n := Length(s);
        while (n > 1) and ((Ord(s[n]) and $C0) = $80) do Dec(n);
        SetLength(s, n - 1);
      end;
      s := s + '...';
    end;
    y := full.Top + (full.Bottom - full.Top - th) div 2 + k;
    LcdOut(c, rr, rr.Left, y, s, ROWTXT, col);
    LcdOut(c, r, P(253) - tw, y, d, ROWTXT, col);
  end;
  if FCount = 0 then
  begin
    SetF(c, FontLat, 11, False, RGB_(120, 140, 115));
    TextAtC(c, LR(9, PLT + 2, 257, 40), 'Drag music files or folders here');
  end;

  { scrollbar (only when needed) }
  if FCount > vis then
  begin
    y := Round((PLT + 2 + (LH - 17) * FListTop / (FCount - vis)) * G);
    ChromeThumb(c, Rect(P(257.5), y, P(264.5), y + P(17)), FDragging = bScroll);
  end;

  { bottom bar: ADD | REMOVE   [elapsed / total]   CLEAR   resize grip }
  SetF(c, FontSmall, 8, False, cLabel);
  Btn(7, 28, 'ADD', bAddMenu);
  Btn(36, 40, 'REMOVE', bSubFile);
  Btn(203, 34, 'CLEAR', bNewList);
  total := 0; unknown := False;
  for i := 0 to FCount - 1 do
    if FTracks[i].Duration > 0 then total := total + FTracks[i].Duration
    else if not FTracks[i].Bad then unknown := True;
  r := LR(87.5, BarCY - 6.5, 100, 13);
  FillC(c, r, cSage);
  Frame3(c, r, RGB_(20, 20, 20), RGB_(120, 120, 120));
  if FState <> psStopped then s := FmtTime(CurPos) else s := '0:00';
  s := s + ' / ' + FmtTime(total);
  if unknown then s := s + '+';
  LcdInRect(c, r, (r.Left + r.Right - LcdWidth(c, s, 9.4)) div 2, s, 9.4, cInk);
  { resize grip: fine anti-aliased diamond outline }
  begin
    t1 := Round(261.5 * G * 2) / 2; t2 := Round(BarCY * G * 2) / 2;
    o1 := 3.4 * G; o2 := o1 - Max(1.0, 1.0 * G) * Sqrt(2);
    FillPolysAA(c, [t1, t2 - o1, t1 + o1, t2, t1, t2 + o1, t1 - o1, t2,
                    t1, t2 - o2, t1 - o2, t2, t1, t2 + o2, t1 + o2, t2], [4, 4], RGB_(170, 170, 170));
  end;
end;

{ ===================== input ===================== }

function TMainForm.HitMain(X, Y: Integer): TBtnId;
begin
  { no minimise button: title bar has shade + close only (same layout as the playlist) }
  if InL(X, Y, 245.5, 0, 10.5, IfThen(FShade, SHADEH, TITLEH)) then Exit(bShade);
  if InL(X, Y, 256.5, 0, 18.5, IfThen(FShade, SHADEH, TITLEH)) then Exit(bClose);
  if FShade then
  begin
    if InL(X, Y, SH_BTN_X - 0.5, 0, 5 * SH_BTN_P, SHADEH) then
      Exit(TBtnId(Ord(bPrev) + EnsureRange(Trunc((X / G - SH_BTN_X + 0.5) / SH_BTN_P), 0, 4)));
    if InL(X, Y, SH_TIME_X - 1, 0, SH_TIME_W + 2, SHADEH) then Exit(bTime);
    if InL(X, Y, SH_SEEK_X - 2, 0, SH_SEEK_W + 4, SHADEH) then Exit(bSeek);
    Exit(bMove);
  end;
  if InL(X, Y, 0, 0, MAINW, TITLEH) then Exit(bMove);
  if InL(X, Y, 13, 23, 80, 16) then Exit(bTime);
  if InL(X, Y, 13, 39, 80, 21) then Exit(bVisToggle);
  if InL(X, Y, 15, 93, 5 * TBW, 11) then Exit(TBtnId(Ord(bPrev) + EnsureRange(Trunc((X / G - 15) / TBW), 0, 4)));
  if InL(X, Y, 243, 91, 23, 15) then Exit(bEject);
  if InL(X, Y, 243, 58, 23, 11) then Exit(bPL);
  if InL(X, Y, 10, 70, 258, 11) then Exit(bSeek);
  if InL(X, Y, 101, 56, 80, 13) then Exit(bVol);
  if InL(X, Y, 181, 56, 56, 13) then Exit(bBal);
  Result := bMove;   { drag the window by any empty area }
end;

function TMainForm.HitPL(X, Y: Integer): TBtnId;
var
  H: Integer;
begin
  H := Round(FPL.ClientHeight / G);
  if InL(X, Y, 245.5, 0, 10.5, IfThen(FPLShade, PL_SHADEH, TITLEH)) then Exit(bPLShade);
  if InL(X, Y, 256.5, 0, 18.5, IfThen(FPLShade, PL_SHADEH, TITLEH)) then Exit(bPLClose);
  if FPLShade then Exit(bPLMove);
  if InL(X, Y, 0, 0, PLW, PLT) then Exit(bPLMove);
  if InL(X, Y, 9, PLT + 2, 247, H - PLT - 4 - PL_BOT) then Exit(bList);
  if InL(X, Y, 256, PLT + 2, 11, H - PLT - 4 - PL_BOT) then Exit(bScroll);
  if InL(X, Y, 7, H - PL_BOT, 28, PL_BOT) then Exit(bAddMenu);
  if InL(X, Y, 36, H - PL_BOT, 40, PL_BOT) then Exit(bSubFile);
  if InL(X, Y, 203, H - PL_BOT, 34, PL_BOT) then Exit(bNewList);
  if InL(X, Y, 250, H - PL_BOT - 2, 25, PL_BOT + 2) then Exit(bResize);
  Result := bPLMove;
end;

procedure TMainForm.UpdateSlider(id: TBtnId; X, Y: Integer);
var
  f: Double;
  vis, H: Integer;
begin
  case id of
    bVol:
      begin
        f := (X / G - 104 - 7) / 60;
        FVolume := EnsureRange(Round(f * 100), 0, 100);
        ApplyVolume;
      end;
    bBal:
      begin
        f := (X / G - 184 - 7) / 36;
        FBalance := EnsureRange(Round(f * 200 - 100), -100, 100);
        if Abs(FBalance) < 10 then FBalance := 0;
        ApplyVolume;
      end;
    bSeek:
      begin
        if FShade then f := (X / G - SH_SEEK_X - 4) / (SH_SEEK_W - 8)
        else f := (X / G - 12 - 14) / 226;
        FSeekFrac := EnsureRange(f, 0, 1);
      end;
    bScroll:
      begin
        vis := VisibleRows;
        H := Round(FPL.ClientHeight / G);
        if FCount > vis then
        begin
          f := (Y / G - PLT - 2 - 8.5) / (H - PLT - 4 - PL_BOT - 17);
          FListTop := EnsureRange(Round(f * (FCount - vis)), 0, FCount - vis);
        end;
      end;
  end;
  InvalidateAll;
end;

function BtnName(id: TBtnId): string;
begin
  case id of
    bPrev: Result := 'prev'; bPlay: Result := 'play'; bPause: Result := 'pause';
    bStop: Result := 'stop'; bNext: Result := 'next'; bShade: Result := 'shade';
  else Result := IntToStr(Ord(id));
  end;
end;

procedure TMainForm.StartMove(W: TForm);
begin
  FMoveWin := W;
  FMoveStart := Mouse.CursorPos;
  FWinStart := Point(W.Left, W.Top);
  FMoveDocked := (W = Self) and IsDocked;
end;

procedure TMainForm.DoMove;
var
  cur: TPoint;
  nx, ny, snap, dx, dy, w, h: Integer;
  wa, o: TRect;
  HaveOther: Boolean;
  procedure SnapX(edge, target: Integer; IsRight: Boolean);
  begin
    if IsRight then
    begin
      if Abs(nx + w - target) <= snap then nx := target - w;
    end
    else if Abs(nx - target) <= snap then nx := target;
  end;
  procedure SnapY(edge, target: Integer; IsBottom: Boolean);
  begin
    if IsBottom then
    begin
      if Abs(ny + h - target) <= snap then ny := target - h;
    end
    else if Abs(ny - target) <= snap then ny := target;
  end;
begin
  if FMoveWin = nil then Exit;
  cur := Mouse.CursorPos;
  nx := FWinStart.X + cur.X - FMoveStart.X;
  ny := FWinStart.Y + cur.Y - FMoveStart.Y;
  w := FMoveWin.Width; h := FMoveWin.Height;
  snap := P(10);
  wa := Screen.MonitorFromPoint(cur).WorkareaRect;
  { snap to screen work area }
  SnapX(0, wa.Left, False); SnapX(0, wa.Right, True);
  SnapY(0, wa.Top, False); SnapY(0, wa.Bottom, True);
  { snap to the other window }
  HaveOther := FPL.Visible and not FMoveDocked;
  if HaveOther then
  begin
    if FMoveWin = Self then o := FPL.BoundsRect else o := BoundsRect;
    if (ny < o.Bottom + snap) and (ny + h > o.Top - snap) then
    begin
      SnapX(0, o.Right, False); SnapX(0, o.Left, True);
      SnapX(0, o.Left, False); SnapX(0, o.Right, True);
    end;
    if (nx < o.Right + snap) and (nx + w > o.Left - snap) then
    begin
      SnapY(0, o.Bottom, False); SnapY(0, o.Top, True);
      SnapY(0, o.Top, False); SnapY(0, o.Bottom, True);
    end;
  end;
  dx := nx - FMoveWin.Left; dy := ny - FMoveWin.Top;
  if (dx = 0) and (dy = 0) then Exit;
  FMoveWin.SetBounds(nx, ny, w, h);
  if FMoveDocked then FPL.SetBounds(FPL.Left + dx, FPL.Top + dy, FPL.Width, FPL.Height);
end;

procedure TMainForm.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id: TBtnId;
begin
  inherited MouseDown(Button, Shift, X, Y);
  G := FScaleMain;
  if Button = mbRight then
  begin
    ShowMainMenu;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  id := HitMain(X, Y);
  case id of
    bMove:
      if ssDouble in Shift then
      begin
        if Y < P(IfThen(FShade, SHADEH, TITLEH)) then DoButton(bShade);
      end
      else StartMove(Self);
    bSeek, bVol, bBal:
      begin
        if (id = bSeek) and not FStream then Exit;
        FDragging := id;
        if id in [bVol, bBal] then ShowOsd(id);
        UpdateSlider(id, X, Y);
      end;
    bTime:
      begin
        FShowRemaining := not FShowRemaining;
        Invalidate;
      end;
    bNone: ;
  else
    begin
      FPressed := id;
      InvalidateAll;
    end;
  end;
end;

procedure TMainForm.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  G := FScaleMain;
  if FMoveWin <> nil then DoMove
  else if FDragging <> bNone then UpdateSlider(FDragging, X, Y)
  else if FShade then SetHover(HitMain(X, Y));
end;

procedure TMainForm.SetHover(id: TBtnId);
begin
  if not (id in [bPrev, bPlay, bPause, bStop, bNext]) then id := bNone;
  if id <> FHover then
  begin
    FHover := id;
    Invalidate;
  end;
end;

procedure TMainForm.MouseLeave;
begin
  inherited MouseLeave;
  SetHover(bNone);
end;

procedure TMainForm.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id: TBtnId;
begin
  inherited MouseUp(Button, Shift, X, Y);
  G := FScaleMain;
  if FMoveWin <> nil then
  begin
    DoMove;
    FMoveWin := nil;
    Exit;
  end;
  if FDragging <> bNone then
  begin
    if (FDragging = bSeek) and FStream then
      nca_seek(FSeekFrac * CurLen);
    if FDragging in [bVol, bBal] then ShowOsd(FDragging);   { keep the readout ~1 s after release }
    FDragging := bNone;
    InvalidateAll;
    Exit;
  end;
  if FPressed <> bNone then
  begin
    id := FPressed;
    FPressed := bNone;
    InvalidateAll;
    if HitMain(X, Y) = id then
    begin
      DoButton(id);
      DebugLog(Format('button %s shade=%s -> state=%d track=%d',
        [BtnName(id), BoolToStr(FShade, True), Ord(FState), FCur + 1]));
    end;
  end;
end;

procedure TMainForm.PLMouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id: TBtnId;
  row, i: Integer;
begin
  if Button = mbRight then
  begin
    ShowMainMenu;
    Exit;
  end;
  if Button <> mbLeft then Exit;
  id := HitPL(X, Y);
  case id of
    bPLMove:
      if (ssDouble in Shift) and (Y < P(IfThen(FPLShade, PL_SHADEH, TITLEH))) then DoButton(bPLShade)
      else StartMove(FPL);
    bScroll:
      begin
        FDragging := bScroll;
        UpdateSlider(bScroll, X, Y);
      end;
    bResize:
      begin
        FDragging := bResize;
        FResizeStartY := Mouse.CursorPos.Y;
        FResizeStartRows := FPLRows;
        FResizeStartH := PLHeight;
      end;
    bList:
      begin
        row := FListTop + Trunc((Y / G - PLT - 3) / ROWH);
        if (row < 0) or (row >= FCount) then
        begin
          for i := 0 to FCount - 1 do FTracks[i].Selected := False;
          FPL.Invalidate;
          Exit;
        end;
        if ssDouble in Shift then
        begin
          UserPlay(row);
          Exit;
        end;
        if ssShift in Shift then
        begin
          if FAnchor < 0 then FAnchor := row;
          for i := 0 to FCount - 1 do
            FTracks[i].Selected := (i >= Min(FAnchor, row)) and (i <= Max(FAnchor, row));
        end
        else if ssCtrl in Shift then
        begin
          FTracks[row].Selected := not FTracks[row].Selected;
          FAnchor := row;
        end
        else
        begin
          for i := 0 to FCount - 1 do FTracks[i].Selected := (i = row);
          FAnchor := row;
        end;
        FFocus := row;
        FPL.Invalidate;
      end;
    bNone: ;
  else
    begin
      FPressed := id;
      InvalidateAll;
    end;
  end;
end;

procedure TMainForm.PLMouseMove(Shift: TShiftState; X, Y: Integer);
var
  rows, side: Integer;
  hd: Double;
  m: Boolean;
begin
  if FMoveWin <> nil then DoMove
  else if FDragging = bResize then
  begin
    { desired logical height follows the mouse; rows snap in whole rows, but
      beside the main window anything within half a row of (or below) the main
      window height locks to exactly that height, tops aligned }
    hd := FResizeStartH + (Mouse.CursorPos.Y - FResizeStartY) / G;
    side := DockSideOf(BoundsRect, FPL.BoundsRect);
    m := (side in [1, 3]) and not FShade and (hd <= MAINH + ROWH / 2);
    rows := EnsureRange(Round((hd - (PLT + 4 + 2 + PL_BOT)) / ROWH), 4, 120);
    if m then rows := Max(4, (MAINH - (PLT + 4 + 2 + PL_BOT)) div ROWH);
    if (rows <> FPLRows) or (m <> FPLMatch) then
    begin
      FPLRows := rows;
      FPLMatch := m;
      if m then FPL.SetBounds(FPL.Left, Top, SP(PLW), SP(PLHeight))
      else FPL.SetBounds(FPL.Left, FPL.Top, SP(PLW), SP(PLHeight));
      FPL.Invalidate;
    end;
  end
  else if FDragging <> bNone then UpdateSlider(FDragging, X, Y);
end;

procedure TMainForm.PLMouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  id: TBtnId;
begin
  if FMoveWin <> nil then
  begin
    DoMove;
    FMoveWin := nil;
    Exit;
  end;
  if FDragging <> bNone then
  begin
    if FDragging = bResize then PLMouseMove(Shift, X, Y);
    FDragging := bNone;
    InvalidateAll;
    Exit;
  end;
  if FPressed <> bNone then
  begin
    id := FPressed;
    FPressed := bNone;
    InvalidateAll;
    if HitPL(X, Y) = id then DoButton(id);
  end;
end;

procedure TMainForm.HandleWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint; var Handled: Boolean);
begin
  Handled := True;
  if Sender = FPL then
  begin
    if WheelDelta > 0 then Dec(FListTop, 3) else Inc(FListTop, 3);
    FListTop := Max(0, Min(FListTop, FCount - VisibleRows));
  end
  else
  begin
    if WheelDelta > 0 then FVolume := Min(100, FVolume + 4) else FVolume := Max(0, FVolume - 4);
    ApplyVolume;
    ShowOsd(bVol);
  end;
  InvalidateAll;
end;

procedure TMainForm.HandleKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var
  i: Integer;
begin
  case Key of
    VK_Z: PrevTrack;
    VK_X: PlayPressed;
    VK_C: TogglePause;
    VK_V: StopPlay;
    VK_B: NextTrack(False);
    VK_L: AddFilesDialog;
    VK_DELETE: RemoveSelected;
    VK_RETURN: if FFocus >= 0 then UserPlay(FFocus);
    VK_UP, VK_DOWN:
      if FCount > 0 then
      begin
        if Key = VK_UP then FFocus := Max(0, FFocus - 1) else FFocus := Min(FCount - 1, FFocus + 1);
        for i := 0 to FCount - 1 do FTracks[i].Selected := (i = FFocus);
        FAnchor := FFocus;
        EnsureVisible(FFocus);
        InvalidateAll;
      end;
    VK_LEFT, VK_RIGHT:
      if FStream then
      begin
        if Key = VK_LEFT then
          nca_seek(Max(0, CurPos - 5))
        else
          nca_seek(Min(CurLen - 0.5, CurPos + 5));
      end;
    VK_HOME, VK_END:
      begin
        if Key = VK_HOME then FListTop := 0 else FListTop := Max(0, FCount - VisibleRows);
        InvalidateAll;
      end;
    VK_A:
      if ssCtrl in Shift then
      begin
        for i := 0 to FCount - 1 do FTracks[i].Selected := True;
        InvalidateAll;
      end;
  else
    Exit;
  end;
  Key := 0;
end;

procedure TMainForm.DoButton(id: TBtnId);
var
  side: Integer;
begin
  case id of
    bClose: Close;
    bMin: Application.Minimize;
    bShade:
      begin
        side := DockSideOf(BoundsRect, FPL.BoundsRect);
        FShade := not FShade;
        if FShade then SetBounds(Left, Top, SM(MAINW), SM(SHADEH)) else SetBounds(Left, Top, SM(MAINW), SM(MAINH));
        if side = 2 then FPL.Top := Top + Height;
        DebugLog(Format('shade=%s scale=%.3f main=%dx%d (expected %dx%d)',
          [BoolToStr(FShade, True), FScaleMain, Width, Height, SM(MAINW), SM(IfThen(FShade, SHADEH, MAINH))]));
        Invalidate;
      end;
    bVisToggle: begin FVisOn := not FVisOn; Invalidate; end;
    bPrev: PrevTrack;
    bPlay: PlayPressed;
    bPause: TogglePause;
    bStop: StopPlay;
    bNext: NextTrack(False);
    bEject: AddFilesDialog;
    bPL: SetPLVisible(not FShowPL);
    bPLClose: SetPLVisible(False);
    bPLShade:
      begin
        FPLShade := not FPLShade;
        FPL.SetBounds(FPL.Left, FPL.Top, SP(PLW), SP(PLHeight));
        FPL.Invalidate;
      end;
    bAddMenu: ShowAddMenu;
    bSubFile: RemoveSelected;
    bNewList: ClearList;
  end;
end;

procedure TMainForm.EnsureVisible(i: Integer);
begin
  if i < 0 then Exit;
  if i < FListTop then FListTop := i
  else if i >= FListTop + VisibleRows then FListTop := i - VisibleRows + 1;
end;

function TMainForm.CurPos: Double;
begin
  Result := 0;
  if AudioLoaded and FStream then
    Result := nca_get_pos();
end;

function TMainForm.CurLen: Double;
begin
  Result := 0;
  if AudioLoaded and FStream then
    Result := nca_get_len();
end;

{ ===================== tray icon (no taskbar button) ===================== }

procedure TMainForm.BuildTray;
begin
  { own Shell_NotifyIconW icon (NOTIFYICON_VERSION_4) on a hidden PMv2 window }
  FTray := TNcTray.Create(APPNAME);
  FTray.OnLog := @TrayLog;
  FTray.OnClick := @TrayClick;
  FTray.OnMenu := @TrayMenu;
  FTray.Show;
  FTrayTip := APPNAME;
  Application.AddOnDeactivateHandler(@AppDeactivate);
end;

procedure TMainForm.TrayLog(const s: string);
begin
  DebugLog(s);
end;

procedure TMainForm.AppDeactivate(Sender: TObject);
begin
  FDeactTick := GetTickCount64;   { clicking the tray icon activates the taskbar first }
end;

function TMainForm.AppVisibleAndActive: Boolean;
var
  fg: HWND;
begin
  fg := GetForegroundWindow;
  Result := Visible and ((fg = Handle) or (FPL.HandleAllocated and (fg = FPL.Handle))
    or (GetTickCount64 - FDeactTick < 700));
end;

procedure TMainForm.ShowApp;
begin
  if not Visible then Show;
  if FShowPL and not FPL.Visible then FPL.Show;
  if FShowPL then FPL.BringToFront;
  BringToFront;
  SetForegroundWindow(Handle);
  DebugLog('tray: show');
end;

procedure TMainForm.HideApp;
begin
  if FPL.Visible then FPL.Hide;   { FShowPL is kept, the playlist returns with Show }
  Hide;
  DebugLog('tray: hide');
end;

procedure TMainForm.TrayClick;
begin
  { left click: hidden -> show; visible but behind -> bring to front; in front -> hide }
  if AppVisibleAndActive then HideApp else ShowApp;
end;

procedure TMainForm.TrayMenu(X, Y: Integer);
var
  id: Integer;
  pp, sh: string;
  mo: HWND;
begin
  if FState = psPlaying then pp := 'Pause' else pp := 'Play';
  if Visible then sh := 'Bring to front' else sh := 'Show';
  { owner = fresh hidden PMv2 window on the monitor where the menu opens (the
    taskbar's), not the main window, which may sit on a monitor with another DPI }
  mo := CreateMenuOwner(X, Y);
  if mo = 0 then mo := Handle;
  id := NativePopup(mo, [NM(pp, 1), NM('Next', 2), NM('Previous', 3), NM('Stop', 4),
    NM('-', 0), NM(sh, 5), NM('-', 0), NM('Exit', 6)], True, X, Y);
  if mo <> Handle then DestroyWindow(mo);
  case id of
    1: if FState = psStopped then PlayPressed else TogglePause;
    2: NextTrack(False);
    3: PrevTrack;
    4: StopPlay;
    5: ShowApp;
    6: Close;
  end;
  DebugLog(Format('tray menu %d -> state=%d track=%d', [id, Ord(FState), FCur]));
  Invalidate;
  if FPL.Visible then FPL.Invalidate;
end;

procedure TMainForm.UpdateTrayTip;
var
  t: string;
begin
  if FTray = nil then Exit;
  if (FCur >= 0) and (FCur < FCount) and (FState <> psStopped) then
  begin
    t := DisplayTitle(FCur);
    if FState = psPaused then t := t + ' (paused)';
    t := APPNAME + #10 + t;
  end
  else
    t := APPNAME + ' - ' + IntToStr(FCount) + ' tracks';
  if UTF8Length(t) > 120 then t := UTF8Copy(t, 1, 117) + '...';   { NOTIFYICONDATAW.szTip = 128 }
  if t <> FTrayTip then
  begin
    FTrayTip := t;
    FTray.SetTip(t);
  end;
end;

function TMainForm.DisplayTitle(i: Integer): string;
begin
  if (i < 0) or (i >= FCount) then Exit('');
  Result := FTracks[i].Title;
  if Result = '' then Result := ExtractFileNameOnly(FTracks[i].Path);
end;

{ ===================== playlist / playback logic ===================== }
{ ---------- playlist management ---------- }

procedure TMainForm.AddOne(const fn: string);
begin
  if FCount >= Length(FTracks) then SetLength(FTracks, Max(64, FCount * 2));
  FTracks[FCount].Path := fn;
  FTracks[FCount].Title := '';
  FTracks[FCount].Duration := -1;
  FTracks[FCount].Scanned := False;
  FTracks[FCount].Bad := False;
  FTracks[FCount].Selected := False;
  FTracks[FCount].Id := FNextId;
  Inc(FNextId);
  Inc(FCount);
end;

function IsAudioFile(const fn: string): Boolean;
var
  e: string;
begin
  e := LowerCase(ExtractFileExt(fn));
  Result := (e <> '') and (Pos('*' + e + ';', AUDIO_MASK + ';') > 0);
end;

function TMainForm.AddPaths(const Paths: array of string): Integer;
var
  i, j, oldCount, p, t: Integer;
  L: TStringList;
begin
  oldCount := FCount;
  for i := 0 to High(Paths) do
  begin
    if DirectoryExists(Paths[i]) then
    begin
      L := FindAllFiles(Paths[i], AUDIO_MASK, True);
      try
        L.Sort;
        for j := 0 to L.Count - 1 do AddOne(L[j]);
      finally
        L.Free;
      end;
    end
    else if FileExists(Paths[i]) and (IsAudioFile(Paths[i]) or
      (LowerCase(ExtractFileExt(Paths[i])) = '.m3u') or (LowerCase(ExtractFileExt(Paths[i])) = '.m3u8')) then
    begin
      if Pos('.m3u', LowerCase(ExtractFileExt(Paths[i]))) = 1 then
      begin
        L := TStringList.Create;
        try
          L.LoadFromFile(Paths[i]);
          for j := 0 to L.Count - 1 do
            if (Trim(L[j]) <> '') and (Trim(L[j])[1] <> '#') then
            begin
              if FileExists(Trim(L[j])) then AddOne(Trim(L[j]))
              else if FileExists(ExtractFilePath(Paths[i]) + Trim(L[j])) then
                AddOne(ExtractFilePath(Paths[i]) + Trim(L[j]));
            end;
        finally
          L.Free;
        end;
      end
      else
        AddOne(Paths[i]);
    end;
  end;
  Result := FCount - oldCount;
  { keep an existing shuffle order valid: insert new tracks at random
    positions among the not-yet-played part }
  if FShuffle and (Result > 0) then
  begin
    if Length(FOrder) <> oldCount then
    begin
      BuildShuffle(FCur, -1);
      if FCur < 0 then FOrderPos := -1 else FOrderPos := 0;
    end
    else
    begin
      SetLength(FOrder, FCount);
      for j := oldCount to FCount - 1 do
      begin
        p := FOrderPos + 1 + Random(j - FOrderPos);   { position in [FOrderPos+1 .. j] }
        if p < 0 then p := 0;
        for t := j downto p + 1 do FOrder[t] := FOrder[t - 1];
        FOrder[p] := j;
      end;
    end;
  end;
  InvalidateAll;
end;

procedure TMainForm.BuildShuffle(First, AvoidFirst: Integer);
var
  i, j, t: Integer;
begin
  SetLength(FOrder, FCount);
  for i := 0 to FCount - 1 do FOrder[i] := i;
  for i := FCount - 1 downto 1 do
  begin
    j := Random(i + 1);
    t := FOrder[i]; FOrder[i] := FOrder[j]; FOrder[j] := t;
  end;
  if (First >= 0) and (First < FCount) then
  begin
    for i := 0 to FCount - 1 do
      if FOrder[i] = First then
      begin
        FOrder[i] := FOrder[0]; FOrder[0] := First;
        Break;
      end;
  end
  else if (AvoidFirst >= 0) and (FCount > 1) and (FOrder[0] = AvoidFirst) then
  begin
    j := 1 + Random(FCount - 1);
    FOrder[0] := FOrder[j]; FOrder[j] := AvoidFirst;
  end;
end;

procedure TMainForm.SetShuffle(On: Boolean);
begin
  FShuffle := On;
  if On then
  begin
    BuildShuffle(FCur, -1);
    if FCur >= 0 then FOrderPos := 0 else FOrderPos := -1;
  end;
  InvalidateAll;
end;

procedure TMainForm.ApplyVolume;
begin
  if AudioLoaded then
  begin
    nca_set_volume(FVolume / 100);
    nca_set_pan(FBalance / 100);
  end;
  InvalidateAll;
end;

procedure TMainForm.PlayIndex(i: Integer);
var
  w: UnicodeString;
  info: TNcaInfo;
  t: string;
begin
  if (i < 0) or (i >= FCount) or not AudioLoaded then Exit;
  FCur := i;
  EnsureVisible(i);
  w := UTF8Decode(FTracks[i].Path);
  FillChar(info, SizeOf(info), 0);
  FStream := nca_open(PWideChar(w), @info) <> 0;
  if not FStream then
  begin
    DebugLog('cannot play ' + FTracks[i].Path + ': ' + string(nca_error()));
    FTracks[i].Bad := True;
    FTracks[i].Scanned := True;
    Inc(FFailStreak);
    FState := psStopped;
    if FFailStreak < FCount then NextTrack(True)
    else
    begin
      FFailStreak := 0;
      FStatusMsg := 'Cannot play: ' + ExtractFileName(FTracks[i].Path);
    end;
    InvalidateAll;
    Exit;
  end;
  FFailStreak := 0;
  FStatusMsg := '';
  FTracks[i].Bad := False;
  if not FTracks[i].Scanned then
  begin
    t := ReadTitle(FTracks[i].Path);
    if t <> '' then FTracks[i].Title := t;
    FTracks[i].Scanned := True;
  end;
  if CurLen > 0 then FTracks[i].Duration := CurLen;
  FFreq := info.SampleRate;
  FChans := info.Channels;
  FBitrate := info.Bitrate;
  if FBitrate <= 0 then FBitrate := Round(info.SampleRate * info.Channels * 16 / 1000);
  ApplyVolume;
  nca_play();
  FState := psPlaying;
  FMarqueeOfs := 0;
  DebugLog(Format('play %d %s [%s %d Hz %d ch %d kbps %.1f s]', [i + 1, DisplayTitle(i),
    string(PAnsiChar(@info.Codec[0])), info.SampleRate, info.Channels, info.Bitrate, CurLen]));
  InvalidateAll;
end;

procedure TMainForm.UserPlay(i: Integer);
begin
  if FShuffle then
  begin
    BuildShuffle(i, -1);
    FOrderPos := 0;
  end;
  PlayIndex(i);
end;

procedure TMainForm.NextTrack(Auto: Boolean);
var
  i, last: Integer;
begin
  if FCount = 0 then Exit;
  if FShuffle then
  begin
    if Length(FOrder) <> FCount then
    begin
      BuildShuffle(FCur, -1);
      if FCur >= 0 then FOrderPos := 0 else FOrderPos := -1;
    end;
    Inc(FOrderPos);
    if FOrderPos >= FCount then
    begin
      if FRepeat or not Auto then
      begin
        last := FOrder[FCount - 1];
        BuildShuffle(-1, last);     { new round; never starts with the track just played }
        FOrderPos := 0;
      end
      else
      begin
        FOrderPos := FCount - 1;
        StopPlay;
        Exit;
      end;
    end;
    PlayIndex(FOrder[FOrderPos]);
  end
  else
  begin
    i := FCur + 1;
    if i >= FCount then
    begin
      if FRepeat or not Auto then i := 0
      else
      begin
        StopPlay;
        Exit;
      end;
    end;
    PlayIndex(i);
  end;
end;

procedure TMainForm.PrevTrack;
var
  i: Integer;
begin
  if FCount = 0 then Exit;
  if FShuffle and (Length(FOrder) = FCount) then
  begin
    if FOrderPos > 0 then Dec(FOrderPos) else FOrderPos := FCount - 1;
    PlayIndex(FOrder[FOrderPos]);
  end
  else
  begin
    i := FCur - 1;
    if i < 0 then i := FCount - 1;
    PlayIndex(i);
  end;
end;

procedure TMainForm.StopPlay;
begin
  if AudioLoaded and FStream then
  begin
    nca_stop();
  end;
  FState := psStopped;
  InvalidateAll;
end;

procedure TMainForm.PlayPressed;
var
  i: Integer;
begin
  if FCount = 0 then
  begin
    AddFilesDialog;
    Exit;
  end;
  if (FState = psPaused) and FStream then
  begin
    nca_play();
    FState := psPlaying;
  end
  else if (FState = psStopped) and FStream and (FCur >= 0) and
    ((FFocus < 0) or (FFocus = FCur) or not FTracks[FFocus].Selected) then
  begin
    nca_seek(0);
    nca_play();
    FState := psPlaying;
  end
  else
  begin
    i := FFocus;
    if (i < 0) or not FTracks[i].Selected then i := FCur;
    if i < 0 then
    begin
      if FShuffle then
      begin
        BuildShuffle(-1, -1);
        FOrderPos := 0;
        i := FOrder[0];
        PlayIndex(i);
        Exit;
      end;
      i := 0;
    end;
    UserPlay(i);
  end;
  InvalidateAll;
end;

procedure TMainForm.TogglePause;
begin
  if not FStream then Exit;
  if FState = psPlaying then
  begin
    nca_pause();
    FState := psPaused;
  end
  else if FState = psPaused then
  begin
    nca_play();
    FState := psPlaying;
  end;
  InvalidateAll;
end;

procedure TMainForm.RemoveSelected;
var
  i, n, newCur: Integer;
begin
  n := 0;
  newCur := -1;
  for i := 0 to FCount - 1 do
    if not FTracks[i].Selected then
    begin
      if i = FCur then newCur := n;
      FTracks[n] := FTracks[i];
      Inc(n);
    end;
  if n = FCount then Exit;
  FCount := n;
  FCur := newCur;
  FFocus := Min(FFocus, FCount - 1);
  FAnchor := -1;
  if FScanPos > FCount then FScanPos := FCount;
  FScanPos := 0;
  if FShuffle then
  begin
    BuildShuffle(FCur, -1);
    if FCur >= 0 then FOrderPos := 0 else FOrderPos := -1;
  end;
  InvalidateAll;
end;

procedure TMainForm.ClearList;
begin
  StopPlay;
  if FStream then begin nca_close(); FStream := False; end;
  FCount := 0;
  SetLength(FTracks, 0);
  SetLength(FOrder, 0);
  FOrderPos := -1;
  FCur := -1; FFocus := -1; FAnchor := -1; FListTop := 0; FScanPos := 0;
  FStatusMsg := '';
  InvalidateAll;
end;

procedure TMainForm.AddFilesDialog;
var
  dlg: TOpenDialog;
  arr: array of string;
  i, n0: Integer;
begin
  dlg := TOpenDialog.Create(Self);
  try
    dlg.Title := 'Add music files';
    dlg.Filter := 'Audio files|' + AUDIO_MASK + ';*.m3u;*.m3u8|All files|*.*';
    dlg.Options := dlg.Options + [ofAllowMultiSelect, ofFileMustExist];
    if dlg.Execute then
    begin
      SetLength(arr, dlg.Files.Count);
      for i := 0 to dlg.Files.Count - 1 do arr[i] := dlg.Files[i];
      n0 := FCount;
      if (AddPaths(arr) > 0) and (FState = psStopped) then
      begin
        if FShuffle then UserPlay(n0 + Random(FCount - n0)) else UserPlay(n0);
      end;
    end;
  finally
    dlg.Free;
  end;
end;

procedure TMainForm.AddDirDialog;
var
  dlg: TSelectDirectoryDialog;
  n0: Integer;
begin
  dlg := TSelectDirectoryDialog.Create(Self);
  try
    dlg.Title := 'Add folder (including sub-folders)';
    if dlg.Execute then
    begin
      n0 := FCount;
      if (AddPaths([dlg.FileName]) > 0) and (FState = psStopped) then
      begin
        if FShuffle then UserPlay(n0 + Random(FCount - n0)) else UserPlay(n0);
      end;
    end;
  finally
    dlg.Free;
  end;
end;

{ called inside WM_COPYDATA (the sender is blocked): only copy and post }
procedure TMainForm.IpcRequest(Paths: TStrings);
begin
  FIpcPending.AddStrings(Paths);
  Inc(FIpcRequests);
  PostMessage(Handle, WM_NCAMP_IPC, 0, 0);
end;

procedure TMainForm.HandleIpc;
var
  a: array of string;
  i: Integer;
begin
  if FIpcRequests = 0 then Exit;
  FIpcRequests := 0;
  SetLength(a, FIpcPending.Count);
  for i := 0 to FIpcPending.Count - 1 do a[i] := FIpcPending[i];
  FIpcPending.Clear;
  DebugLog(Format('ipc: %d path(s) from a second instance', [Length(a)]));
  for i := 0 to Min(High(a), 4) do DebugLog('ipc:   ' + a[i]);
  if Length(a) > 0 then OnDrop(nil, a);   { usual drop behaviour: add + shuffle-play all }
  ShowApp;                                { restore if hidden via tray, bring to front }
end;

procedure TMainForm.OnDrop(Sender: TObject; const FileNames: array of string);
var
  added: Integer;
begin
  added := AddPaths(FileNames);
  if added <= 0 then Exit;
  { dropping starts the whole list in shuffled order, looping (reshuffled) forever }
  FShuffle := True;
  FRepeat := True;
  BuildShuffle(-1, -1);
  FOrderPos := 0;
  PlayIndex(FOrder[0]);
  Application.BringToFront;
end;

{ ===================== timer ===================== }

{ Winamp-style value readout in the LCD title line while a slider is dragged / wheeled }
function TMainForm.OsdText: string;
begin
  Result := '';
  if not ((FDragging in [bVol, bBal]) or ((FOsdUntil <> 0) and (GetTickCount64 < FOsdUntil))) then Exit;
  if FDragging in [bVol, bBal] then FOsdSlider := FDragging;
  if FOsdSlider = bVol then Result := Format('Volume: %d%%', [FVolume])
  else if FBalance = 0 then Result := 'Balance: Center'
  else if FBalance < 0 then Result := Format('Balance: %d%% Left', [-FBalance])
  else Result := Format('Balance: %d%% Right', [FBalance]);
end;

procedure TMainForm.ShowOsd(id: TBtnId);
begin
  FOsdSlider := id;
  FOsdUntil := GetTickCount64 + 1000;
  Invalidate;
end;

procedure TMainForm.LogEngine;
var
  s: string;
  p: Integer;
begin
  s := AudioTakeLog;
  while s <> '' do
  begin
    p := Pos(#10, s);
    if p = 0 then p := Length(s) + 1;
    if p > 1 then DebugLog('engine: ' + Copy(s, 1, p - 1));
    Delete(s, 1, p);
  end;
end;

procedure TMainForm.DiagOutput;
var
  cbs, frames: Integer;
  pk: Single;
begin
  pk := nca_take_peak(@cbs, @frames);
  if GetEnvironmentVariable('NCAMP_LOG') = '' then Exit;
  DebugLog(Format('output: peak=%.4f (%.1f dBFS) callbacks=%d frames=%d state=%d pos=%.2f vol=%d bal=%d',
    [pk, 20 * Log10(Max(pk, 1e-9)), cbs, frames, nca_state(), nca_get_pos(), FVolume, FBalance]));
end;

procedure TMainForm.TimerTick(Sender: TObject);
var
  fft: array[0..511] of Single;
  i, j, lo, hi, n: Integer;
  peak, v: Single;
  title: string;
  dur: Double;
  plDirty: Boolean;
begin
  UpdateTrayTip;
  if (FOsdUntil <> 0) and (FDragging = bNone) and (GetTickCount64 >= FOsdUntil) then
  begin
    FOsdUntil := 0;           { readout expired: back to the song title }
    Invalidate;
  end;
  if AudioLoaded then
  begin
    nca_poll();                         { restart a stopped device, log reroutes }
    if GetTickCount64 - FDiagTick >= 3000 then
    begin
      FDiagTick := GetTickCount64;
      DiagOutput;
    end;
    LogEngine;
  end;
  if AudioLoaded and (FState = psPlaying) and FStream then
    if nca_state() = NCA_ENDED then
    begin
      NextTrack(True);
      Exit;
    end;

  if AudioLoaded and FVisOn and (FState = psPlaying) and FStream and
    (nca_get_fft(@fft[0]) <> 0) then
  begin
    lo := 1;
    for i := 0 to NBARS - 1 do
    begin
      hi := Trunc(Power(2, (i + 1) * 9.0 / NBARS));
      if hi <= lo then hi := lo + 1;
      if hi > 511 then hi := 511;
      peak := 0;
      for j := lo to hi - 1 do if fft[j] > peak then peak := fft[j];
      lo := hi;
      v := Sqrt(peak) * 2.2;
      if v > 1 then v := 1;
      if v > FBars[i] then FBars[i] := v
      else FBars[i] := Max(0, FBars[i] - 0.045);
    end;
  end
  else
    for i := 0 to NBARS - 1 do FBars[i] := Max(0, FBars[i] - 0.045);
  for i := 0 to NBARS - 1 do
    if FBars[i] >= FPeaks[i] then
    begin
      FPeaks[i] := FBars[i];
      FPeakVel[i] := 0;
    end
    else
    begin
      FPeakVel[i] := FPeakVel[i] + 0.0025;
      FPeaks[i] := Max(0, FPeaks[i] - FPeakVel[i]);
    end;

  FMarqueeOfs := FMarqueeOfs + 0.6;

  plDirty := False;
  n := 0;
  while (FScanPos < FCount) and (n < 3) do
  begin
    if not FTracks[FScanPos].Scanned then
    begin
      if ReadTrackInfo(FTracks[FScanPos].Path, title, dur) then
      begin
        if title <> '' then FTracks[FScanPos].Title := title;
        FTracks[FScanPos].Duration := dur;
      end
      else
        FTracks[FScanPos].Bad := True;
      FTracks[FScanPos].Scanned := True;
      Inc(n);
      plDirty := True;
    end;
    Inc(FScanPos);
  end;

  if GetTickCount64 - FLastDpiCheck > 500 then
  begin
    FLastDpiCheck := GetTickCount64;
    if FMoveWin = nil then CheckDpi('poll');
  end;
  Invalidate;
  if FPL.Visible and (plDirty or ((GetTickCount64 div 25) mod 8 = 0)) then FPL.Invalidate;
end;

{ ===================== persistence ===================== }

function TMainForm.ConfigDir: string;
var
  buf: array[0..1023] of WideChar;
  n: DWORD;
  base, old: string;
begin
  n := GetEnvironmentVariableW('LOCALAPPDATA', @buf[0], Length(buf));
  if (n > 0) and (n < Length(buf)) then base := UTF8Encode(UnicodeString(PWideChar(@buf[0])))
  else base := ExtractFilePath(ParamStr(0));
  base := IncludeTrailingPathDelimiter(base);
  Result := base + APPNAME + PathDelim;
  if not DirectoryExists(Result) then
  begin
    ForceDirectories(Result);
    { migrate settings from the earlier "RetroAmp" build }
    old := base + 'RetroAmp' + PathDelim;
    if FileExists(old + 'playlist.m3u8') then CopyFile(old + 'playlist.m3u8', Result + 'playlist.m3u8');
    if FileExists(old + 'retroamp.ini') then CopyFile(old + 'retroamp.ini', Result + 'nc-amp.ini');
  end;
end;

procedure TMainForm.SaveState;
var
  dir: string;
  L: TStringList;
  ini: TIniFile;
  i: Integer;
begin
  try
    dir := ConfigDir;
    L := TStringList.Create;
    try
      for i := 0 to FCount - 1 do L.Add(FTracks[i].Path);
      L.SaveToFile(dir + 'playlist.m3u8');
    finally
      L.Free;
    end;
    ini := TIniFile.Create(dir + 'nc-amp.ini');
    try
      ini.WriteInteger('main', 'volume', FVolume);
      ini.WriteInteger('main', 'balance', FBalance);
      ini.WriteBool('main', 'playlist', FShowPL);
      ini.DeleteKey('main', 'ontop');   { setting removed in 1.6.5 }
      ini.WriteBool('main', 'vis', FVisOn);
      ini.WriteBool('main', 'shade', FShade);
      ini.WriteBool('main', 'plshade', FPLShade);
      ini.WriteInteger('main', 'current', FCur);
      ini.WriteInteger('main', 'size', Round(FSizeMul * 10));
      ini.WriteInteger('main', 'plrows', FPLRows);
      ini.WriteInteger('main', 'rowh', ROWH);
      ini.WriteBool('main', 'plmatch', FPLMatch);
      if ShownOnce then
      begin
        ini.WriteInteger('pos', 'left', Left);
        ini.WriteInteger('pos', 'top', Top);
        ini.WriteInteger('pos', 'plleft', FPL.Left);
        ini.WriteInteger('pos', 'pltop', FPL.Top);
      end;
    finally
      ini.Free;
    end;
  except
  end;
end;

procedure TMainForm.LoadState;
var
  dir: string;
  L: TStringList;
  ini: TIniFile;
  i: Integer;
begin
  try
    dir := ConfigDir;
    if FileExists(dir + 'playlist.m3u8') then
    begin
      L := TStringList.Create;
      try
        L.LoadFromFile(dir + 'playlist.m3u8');
        for i := 0 to L.Count - 1 do
          if L[i] <> '' then AddOne(L[i]);
      finally
        L.Free;
      end;
    end;
    if FileExists(dir + 'nc-amp.ini') then
    begin
      ini := TIniFile.Create(dir + 'nc-amp.ini');
      try
        FVolume := EnsureRange(ini.ReadInteger('main', 'volume', 80), 0, 100);
        FBalance := EnsureRange(ini.ReadInteger('main', 'balance', 0), -100, 100);
        FShowPL := ini.ReadBool('main', 'playlist', True);
        FVisOn := ini.ReadBool('main', 'vis', True);
        FShade := ini.ReadBool('main', 'shade', False);
        FPLShade := ini.ReadBool('main', 'plshade', False);
        SetShuffle(True);   { playback is always shuffle + repeat }
        case ini.ReadInteger('main', 'size', 10) of
          15: FSizeMul := 1.5;
          20: FSizeMul := 2.0;
        else FSizeMul := 1.0;
        end;
        FPLRows := ini.ReadInteger('main', 'plrows', 24);
        { rows saved by an older build with a different row height: keep the window height }
        if ini.ReadInteger('main', 'rowh', 15) <> ROWH then
          FPLRows := Round(FPLRows * ini.ReadInteger('main', 'rowh', 15) / ROWH);
        FPLRows := EnsureRange(FPLRows, 4, 120);
        FPLMatch := ini.ReadBool('main', 'plmatch', False);
        FFocus := ini.ReadInteger('main', 'current', -1);
        if FFocus >= FCount then FFocus := -1;
        if FFocus >= 0 then
        begin
          FTracks[FFocus].Selected := True;
          EnsureVisible(FFocus);
        end;
        if ini.ValueExists('pos', 'left') then
        begin
          HaveSavedPos := True;
          SavedMainPos := Point(ini.ReadInteger('pos', 'left', 0), ini.ReadInteger('pos', 'top', 0));
          SavedPLPos := Point(ini.ReadInteger('pos', 'plleft', 0), ini.ReadInteger('pos', 'pltop', 0));
        end;
      finally
        ini.Free;
      end;
    end;
  except
  end;
end;

end.
