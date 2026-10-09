{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit TitleFont;
{ nc-amp title lettering.  The glyphs of 'nc-amp' from Audiowide Regular
  (c) 2012 Astigmatic (AOETI), SIL Open Font License 1.1, are converted to
  vector contours at build time (assets/fonts/mkglyphs.py -> titleglyphs.inc) and
  rasterised here with analytic horizontal + 5x vertical anti-aliasing at the
  exact pixel size for the current DPI/size, then alpha-blended (white print
  with a crisp drop shadow).  Results are cached per size. }
{$mode objfpc}{$H+}
interface

uses Windows, Graphics;

{ x-height and tracking in device pixels; returns drawn width }
function TitleWidth(XH, Track: Double): Integer;
procedure DrawTitle(c: TCanvas; X, BaseY: Integer; XH, Track: Double;
  Face, Shadow: TColor; ShadowOff: Integer);
procedure FreeTitleCache;
{ anti-aliased polygon fill (non-zero winding); Pts = x,y pairs in device px,
  Counts = number of points per contour }
procedure FillPolysAA(c: TCanvas; const Pts: array of Double; const Counts: array of Integer; Col: TColor);

implementation

uses Math;

{$I titleglyphs.inc}

type
  TCacheEnt = record
    XH, Track: Double; Face, Shadow: TColor; Off: Integer;
    Bmp: HBITMAP; W, H, OX, BY: Integer;
  end;

var
  Cache: array[0..3] of TCacheEnt;
  CacheNext: Integer = 0;

function AlphaBlendX(hdcDest: HDC; xD, yD, wD, hD: Integer; hdcSrc: HDC;
  xS, yS, wS, hS: Integer; blend: DWORD): BOOL; stdcall; external 'msimg32.dll' name 'AlphaBlend';

function TitleWidth(XH, Track: Double): Integer;
var
  i: Integer; k, w: Double;
begin
  k := XH / TG_XHEIGHT; w := 0;
  for i := 0 to High(TG_ADV) do w := w + TG_ADV[i] * k;
  w := w + Track * High(TG_ADV);
  Result := Ceil(w);
end;

function Build(XH, Track: Double; Face, Shadow: TColor; Off: Integer): TCacheEnt;
type
  TEdge = record x0, y0, x1, y1: Double; end;
var
  k, pen, minY, maxY, sy, xa, t: Double;
  edges: array of TEdge;
  xs: array of Double; ds: array of Integer;
  cov: array of Single;
  ne, i, j, g, ci, p0, p1, n, W, H, OX, BY, y, s, nx, wind, px, a, b: Integer;
  bi: TBitmapInfo; bits: PByte; q: PByte;
  af, ash, ao, fr, fg, fb, sr, sg, sb: Double;
const
  SS = 5;

  procedure AddEdge(ax, ay, bx, by_: Double);
  begin
    if ay = by_ then Exit;
    if ne >= Length(edges) then SetLength(edges, ne * 2 + 64);
    edges[ne].x0 := ax; edges[ne].y0 := ay; edges[ne].x1 := bx; edges[ne].y1 := by_;
    Inc(ne);
  end;

  procedure Span(row: Integer; x0, x1: Double);
  var
    p, pa, pb: Integer; ov: Double;
  begin
    if x1 <= x0 then Exit;
    pa := Max(0, Floor(x0)); pb := Min(W - 1, Floor(x1));
    for p := pa to pb do
    begin
      ov := Min(x1, p + 1) - Max(x0, p);
      if ov > 0 then cov[row * W + p] := cov[row * W + p] + ov / SS;
    end;
  end;

begin
  k := XH / TG_XHEIGHT;
  minY := 1e9; maxY := -1e9;
  for i := 0 to High(TG_PTS) div 2 do
  begin
    minY := Min(minY, TG_PTS[i * 2 + 1]); maxY := Max(maxY, TG_PTS[i * 2 + 1]);
  end;
  OX := 1;
  BY := Ceil(maxY * k) + 1;
  W := TitleWidth(XH, Track) + OX + Off + 3;
  H := BY + Ceil(-Min(0, minY) * k) + Off + 3;
  { edges in pixel space }
  ne := 0; SetLength(edges, 0);
  pen := OX;
  for g := 0 to High(TG_ADV) do
  begin
    for ci := TG_GFIRST[g] to TG_GFIRST[g] + TG_GCOUNT[g] - 1 do
    begin
      p0 := TG_CSTART[ci]; p1 := TG_CSTART[ci + 1] - 1;
      for j := p0 to p1 do
      begin
        if j < p1 then n := j + 1 else n := p0;
        AddEdge(pen + TG_PTS[j * 2] * k, BY - TG_PTS[j * 2 + 1] * k,
                pen + TG_PTS[n * 2] * k, BY - TG_PTS[n * 2 + 1] * k);
      end;
    end;
    pen := pen + TG_ADV[g] * k + Track;
  end;
  { coverage, non-zero winding }
  SetLength(cov, W * H);
  for i := 0 to High(cov) do cov[i] := 0;
  SetLength(xs, ne); SetLength(ds, ne);
  for y := 0 to H - 1 do
    for s := 0 to SS - 1 do
    begin
      sy := y + (s + 0.5) / SS;
      nx := 0;
      for i := 0 to ne - 1 do
        with edges[i] do
          if ((y0 <= sy) and (y1 > sy)) or ((y1 <= sy) and (y0 > sy)) then
          begin
            t := (sy - y0) / (y1 - y0);
            xa := x0 + t * (x1 - x0);
            j := nx;  { insertion sort }
            while (j > 0) and (xs[j - 1] > xa) do
            begin
              xs[j] := xs[j - 1]; ds[j] := ds[j - 1]; Dec(j);
            end;
            xs[j] := xa;
            if y1 > y0 then ds[j] := 1 else ds[j] := -1;
            Inc(nx);
          end;
      wind := 0;
      for i := 0 to nx - 1 do
      begin
        if (wind = 0) and (i < nx - 1) then xa := xs[i];
        Inc(wind, ds[i]);
        if wind = 0 then Span(y, xa, xs[i]);
      end;
    end;
  { premultiplied BGRA: face over offset shadow }
  FillChar(bi, SizeOf(bi), 0);
  bi.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  bi.bmiHeader.biWidth := W; bi.bmiHeader.biHeight := -H;
  bi.bmiHeader.biPlanes := 1; bi.bmiHeader.biBitCount := 32;
  bi.bmiHeader.biCompression := BI_RGB;
  bits := nil;
  Result.Bmp := CreateDIBSection(0, bi, DIB_RGB_COLORS, Pointer(bits), 0, 0);
  fr := GetRValue(ColorToRGB(Face)); fg := GetGValue(ColorToRGB(Face)); fb := GetBValue(ColorToRGB(Face));
  sr := GetRValue(ColorToRGB(Shadow)); sg := GetGValue(ColorToRGB(Shadow)); sb := GetBValue(ColorToRGB(Shadow));
  if (Result.Bmp <> 0) and (bits <> nil) then
    for y := 0 to H - 1 do
      for px := 0 to W - 1 do
      begin
        af := Min(1, cov[y * W + px]);
        a := px - Off; b := y - Off;
        if (a >= 0) and (b >= 0) then ash := Min(1, cov[b * W + a]) else ash := 0;
        ao := af + ash * (1 - af);
        q := bits + (y * W + px) * 4;
        q[0] := Round(fb * af + sb * ash * (1 - af));
        q[1] := Round(fg * af + sg * ash * (1 - af));
        q[2] := Round(fr * af + sr * ash * (1 - af));
        q[3] := Round(ao * 255);
      end;
  Result.XH := XH; Result.Track := Track; Result.Face := Face;
  Result.Shadow := Shadow; Result.Off := Off;
  Result.W := W; Result.H := H; Result.OX := OX; Result.BY := BY;
end;

procedure DrawTitle(c: TCanvas; X, BaseY: Integer; XH, Track: Double;
  Face, Shadow: TColor; ShadowOff: Integer);
var
  i, idx: Integer;
  dc: HDC; old: HGDIOBJ;
begin
  idx := -1;
  for i := 0 to High(Cache) do
    if (Cache[i].Bmp <> 0) and SameValue(Cache[i].XH, XH, 1e-6) and SameValue(Cache[i].Track, Track, 1e-6)
       and (Cache[i].Face = Face) and (Cache[i].Shadow = Shadow) and (Cache[i].Off = ShadowOff) then idx := i;
  if idx < 0 then
  begin
    idx := CacheNext; CacheNext := (CacheNext + 1) mod Length(Cache);
    if Cache[idx].Bmp <> 0 then DeleteObject(Cache[idx].Bmp);
    Cache[idx] := Build(XH, Track, Face, Shadow, ShadowOff);
    if Cache[idx].Bmp = 0 then Exit;
  end;
  with Cache[idx] do
  begin
    dc := CreateCompatibleDC(c.Handle);
    old := SelectObject(dc, Bmp);
    AlphaBlendX(c.Handle, X - OX, BaseY - BY, W, H, dc, 0, 0, W, H,
      DWORD(0) or (DWORD(0) shl 8) or (DWORD(255) shl 16) or (DWORD(1) shl 24));
    SelectObject(dc, old);
    DeleteDC(dc);
  end;
end;

procedure FillPolysAA(c: TCanvas; const Pts: array of Double; const Counts: array of Integer; Col: TColor);
const
  SS = 5;
var
  minX, minY, maxX, maxY, sy, t, xa, ax, ay, bx, by_: Double;
  X0, Y0, W, H, i, j, k, n, base, y, sub, nx, wind, px, pa, pb: Integer;
  ex0, ey0, ex1, ey1: array of Double;
  xs: array of Double; ds: array of Integer;
  cov: array of Single;
  bi: TBitmapInfo; bits: PByte; q: PByte; bmp: HBITMAP; dc: HDC; old: HGDIOBJ;
  a, cr, cg, cb, ov: Double;
begin
  n := Length(Pts) div 2;
  if n < 3 then Exit;
  minX := 1e9; minY := 1e9; maxX := -1e9; maxY := -1e9;
  for i := 0 to n - 1 do
  begin
    minX := Min(minX, Pts[i * 2]); maxX := Max(maxX, Pts[i * 2]);
    minY := Min(minY, Pts[i * 2 + 1]); maxY := Max(maxY, Pts[i * 2 + 1]);
  end;
  X0 := Floor(minX); Y0 := Floor(minY);
  W := Ceil(maxX) - X0 + 1; H := Ceil(maxY) - Y0 + 1;
  if (W <= 0) or (H <= 0) or (W > 4000) or (H > 4000) then Exit;
  SetLength(ex0, n); SetLength(ey0, n); SetLength(ex1, n); SetLength(ey1, n);
  k := 0; base := 0;
  for j := 0 to High(Counts) do
  begin
    for i := 0 to Counts[j] - 1 do
    begin
      ax := Pts[(base + i) * 2] - X0; ay := Pts[(base + i) * 2 + 1] - Y0;
      if i < Counts[j] - 1 then
      begin bx := Pts[(base + i + 1) * 2] - X0; by_ := Pts[(base + i + 1) * 2 + 1] - Y0; end
      else
      begin bx := Pts[base * 2] - X0; by_ := Pts[base * 2 + 1] - Y0; end;
      if ay <> by_ then
      begin
        ex0[k] := ax; ey0[k] := ay; ex1[k] := bx; ey1[k] := by_; Inc(k);
      end;
    end;
    Inc(base, Counts[j]);
  end;
  SetLength(cov, W * H);
  for i := 0 to High(cov) do cov[i] := 0;
  SetLength(xs, k + 1); SetLength(ds, k + 1);
  for y := 0 to H - 1 do
    for sub := 0 to SS - 1 do
    begin
      sy := y + (sub + 0.5) / SS;
      nx := 0;
      for i := 0 to k - 1 do
        if ((ey0[i] <= sy) and (ey1[i] > sy)) or ((ey1[i] <= sy) and (ey0[i] > sy)) then
        begin
          t := (sy - ey0[i]) / (ey1[i] - ey0[i]);
          xa := ex0[i] + t * (ex1[i] - ex0[i]);
          j := nx;
          while (j > 0) and (xs[j - 1] > xa) do
          begin xs[j] := xs[j - 1]; ds[j] := ds[j - 1]; Dec(j); end;
          xs[j] := xa;
          if ey1[i] > ey0[i] then ds[j] := 1 else ds[j] := -1;
          Inc(nx);
        end;
      wind := 0; xa := 0;
      for i := 0 to nx - 1 do
      begin
        if wind = 0 then xa := xs[i];
        Inc(wind, ds[i]);
        if wind = 0 then
        begin
          pa := Max(0, Floor(xa)); pb := Min(W - 1, Floor(xs[i]));
          for px := pa to pb do
          begin
            ov := Min(xs[i], px + 1) - Max(xa, px);
            if ov > 0 then cov[y * W + px] := cov[y * W + px] + ov / SS;
          end;
        end;
      end;
    end;
  FillChar(bi, SizeOf(bi), 0);
  bi.bmiHeader.biSize := SizeOf(TBitmapInfoHeader);
  bi.bmiHeader.biWidth := W; bi.bmiHeader.biHeight := -H;
  bi.bmiHeader.biPlanes := 1; bi.bmiHeader.biBitCount := 32;
  bi.bmiHeader.biCompression := BI_RGB;
  bits := nil;
  bmp := CreateDIBSection(0, bi, DIB_RGB_COLORS, Pointer(bits), 0, 0);
  if (bmp = 0) or (bits = nil) then Exit;
  cr := GetRValue(ColorToRGB(Col)); cg := GetGValue(ColorToRGB(Col)); cb := GetBValue(ColorToRGB(Col));
  for i := 0 to W * H - 1 do
  begin
    a := Min(1, cov[i]);
    q := bits + i * 4;
    q[0] := Round(cb * a); q[1] := Round(cg * a); q[2] := Round(cr * a); q[3] := Round(a * 255);
  end;
  dc := CreateCompatibleDC(c.Handle);
  old := SelectObject(dc, bmp);
  AlphaBlendX(c.Handle, X0, Y0, W, H, dc, 0, 0, W, H,
    DWORD(0) or (DWORD(0) shl 8) or (DWORD(255) shl 16) or (DWORD(1) shl 24));
  SelectObject(dc, old);
  DeleteDC(dc);
  DeleteObject(bmp);
end;

procedure FreeTitleCache;
var
  i: Integer;
begin
  for i := 0 to High(Cache) do
    if Cache[i].Bmp <> 0 then
    begin
      DeleteObject(Cache[i].Bmp); Cache[i].Bmp := 0;
    end;
end;

finalization
  FreeTitleCache;
end.
