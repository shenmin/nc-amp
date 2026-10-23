{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcTest;
{ Test driver for the macOS build (inert unless NCAMP_TEST_DRIVER=1 is set in the environment).
  It lets an automated test see and operate the windows without Screen Recording / Accessibility
  permissions: it only touches this process' own windows.
  Every 0.25 s the file /tmp/nc-test-cmd is read (and deleted); one command per line:
    snap <name>                    PNG of every window -> /tmp/nc-snap-<name>-<n>.png (backing scale)
    windows                        frames of all windows -> /tmp/nc-test.log
    click <n> <x> <y> [clicks]     left click at x,y (points from the window's top-left)
    rclick <n> <x> <y>             right click (opens the native context menu)
    drag <n> <x1> <y1> <x2> <y2>   press, move, release
    move <n> <x> <y>               mouse moved (tooltips)
    key <characters> [keyCode]     key press to the key window
  Results and errors are appended to /tmp/nc-test.log. }
{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

implementation

uses Classes, SysUtils, CocoaAll, MacOSAll;

type
  TQPt = record x, y: Double; end;
  TNcTestDriver = objcclass(NSObject)
    procedure tick(t: NSTimer); message 'tick:';
  end;

function CGWarpMouseCursorPosition(p: TQPt): Integer; external name '_CGWarpMouseCursorPosition';

var
  GDriver: TNcTestDriver = nil;

procedure TLog(const s: string);
var
  f: TextFile;
begin
  AssignFile(f, '/tmp/nc-test.log');
  if FileExists('/tmp/nc-test.log') then Append(f) else Rewrite(f);
  WriteLn(f, FormatDateTime('hh:nn:ss.zzz', Now), ' ', s);
  CloseFile(f);
end;

function WinAt(n: Integer): NSWindow;
var
  i, k: Integer;
  w: NSWindow;
begin
  Result := nil; k := 0;
  if NSApp = nil then Exit;
  for i := 0 to NSApp.windows.count - 1 do
  begin
    w := NSWindow(NSApp.windows.objectAtIndex(i));
    if (w.contentView = nil) or (w.frame.size.width < 20) then Continue;
    if k = n then begin Result := w; Exit; end;
    Inc(k);
  end;
end;

{ the app reads the real pointer position (Mouse.CursorPos) for dragging and hover tests, so the
  pointer is moved to the target first }
procedure WarpTo(w: NSWindow; x, y: Double);
var
  q: TQPt;
  scr: NSScreen;
begin
  scr := NSScreen(NSScreen.screens.objectAtIndex(0));
  q.x := w.frame.origin.x + x;
  q.y := scr.frame.size.height - (w.frame.origin.y + w.frame.size.height) + y;
  CGWarpMouseCursorPosition(q);
end;

procedure PostMouse(w: NSWindow; typ: NSEventType; x, y: Double; clicks: Integer);
var
  ev: NSEvent;
  p: NSPoint;
begin
  WarpTo(w, x, y);
  p.x := x; p.y := w.contentView.bounds.size.height - y;
  ev := NSEvent.mouseEventWithType_location_modifierFlags_timestamp_windowNumber_context_eventNumber_clickCount_pressure(
    typ, p, 0, NSProcessInfo.processInfo.systemUptime, w.windowNumber, nil, 0, clicks, 1.0);
  NSApp.postEvent_atStart(ev, False);
end;

procedure Snap(const name: string);
var
  n: Integer;
  w: NSWindow;
  v: NSView;
  rep: NSBitmapImageRep;
  data: NSData;
  sc: Double;
  cs: CGColorSpaceRef;
  ctx: CGContextRef;
  img: CGImageRef;
begin
  n := 0;
  repeat
    w := WinAt(n);
    if w = nil then Break;
    if w.isVisible then
    begin
      v := w.contentView;
      sc := StrToFloatDef(GetEnvironmentVariable('NCAMP_TEST_SCALE'), 1);   { snapshot at this backing scale }
      cs := CGColorSpaceCreateDeviceRGB;
      ctx := CGBitmapContextCreate(nil, Round(v.bounds.size.width * sc), Round(v.bounds.size.height * sc), 8, 0, cs,
        kCGImageAlphaPremultipliedFirst or kCGBitmapByteOrder32Little);
      CGContextScaleCTM(ctx, sc, sc);
      v.displayRectIgnoringOpacity_inContext(v.bounds, NSGraphicsContext.graphicsContextWithGraphicsPort_flipped(ctx, False));
      img := CGBitmapContextCreateImage(ctx);
      rep := NSBitmapImageRep.alloc.initWithCGImage(img);
      CGImageRelease(img); CGContextRelease(ctx); CGColorSpaceRelease(cs);
      data := rep.representationUsingType_properties(NSPNGFileType, nil);
      data.writeToFile_atomically(NSSTR(PChar(Format('/tmp/nc-snap-%s-%d.png', [name, n]))), True);
      TLog(Format('snap %s window %d: %dx%d px', [name, n, rep.pixelsWide, rep.pixelsHigh]));
    end;
    Inc(n);
  until False;
end;

procedure Run(const line: string);
var
  a: TStringList;
  w: NSWindow;
  n, i, clicks: Integer;
  ev: NSEvent;
  chars: NSString;
  x1, y1, x2, y2: Double;
begin
  a := TStringList.Create;
  try
    a.Delimiter := ' '; a.StrictDelimiter := True; a.DelimitedText := Trim(line);
    if a.Count = 0 then Exit;
    if a[0] = 'snap' then begin Snap(a[1]); Exit; end;
    if a[0] = 'windows' then
    begin
      n := 0;
      repeat
        w := WinAt(n); if w = nil then Break;
        TLog(Format('window %d: x=%.0f y=%.0f w=%.0f h=%.0f visible=%d key=%d', [n, w.frame.origin.x,
          w.frame.origin.y, w.frame.size.width, w.frame.size.height, Ord(w.isVisible), Ord(w.isKeyWindow)]));
        Inc(n);
      until False;
      Exit;
    end;
    if a[0] = 'key' then
    begin
      w := NSApp.keyWindow; if w = nil then w := WinAt(0);
      chars := NSSTR(PChar(a[1]));
      i := 0; if a.Count > 2 then i := StrToIntDef(a[2], 0);
      ev := NSEvent.keyEventWithType_location_modifierFlags_timestamp_windowNumber_context_characters_charactersIgnoringModifiers_isARepeat_keyCode(
        NSKeyDown, NSMakePoint(0, 0), 0, NSProcessInfo.processInfo.systemUptime, w.windowNumber, nil, chars, chars, False, i);
      NSApp.postEvent_atStart(ev, False);
      ev := NSEvent.keyEventWithType_location_modifierFlags_timestamp_windowNumber_context_characters_charactersIgnoringModifiers_isARepeat_keyCode(
        NSKeyUp, NSMakePoint(0, 0), 0, NSProcessInfo.processInfo.systemUptime, w.windowNumber, nil, chars, chars, False, i);
      NSApp.postEvent_atStart(ev, False);
      Exit;
    end;
    w := WinAt(StrToIntDef(a[1], 0));
    if w = nil then begin TLog('no window ' + a[1]); Exit; end;
    x1 := StrToFloat(a[2]); y1 := StrToFloat(a[3]);
    if a[0] = 'click' then
    begin
      clicks := 1; if a.Count > 4 then clicks := StrToIntDef(a[4], 1);
      PostMouse(w, NSLeftMouseDown, x1, y1, clicks);
      PostMouse(w, NSLeftMouseUp, x1, y1, clicks);
    end
    else if a[0] = 'rclick' then
    begin
      PostMouse(w, NSRightMouseDown, x1, y1, 1);
      PostMouse(w, NSRightMouseUp, x1, y1, 1);
    end
    else if a[0] = 'move' then PostMouse(w, NSMouseMoved, x1, y1, 0)
    else if a[0] = 'drag' then
    begin
      x2 := StrToFloat(a[4]); y2 := StrToFloat(a[5]);
      PostMouse(w, NSLeftMouseDown, x1, y1, 1);
      for i := 1 to 10 do PostMouse(w, NSLeftMouseDragged, x1 + (x2 - x1) * i / 10, y1 + (y2 - y1) * i / 10, 1);
      PostMouse(w, NSLeftMouseUp, x2, y2, 1);
    end
    else TLog('unknown command ' + line);
  finally
    a.Free;
  end;
end;

procedure TNcTestDriver.tick(t: NSTimer);
var
  l: TStringList;
  i: Integer;
begin
  if not FileExists('/tmp/nc-test-cmd') then Exit;
  l := TStringList.Create;
  try
    try
      l.LoadFromFile('/tmp/nc-test-cmd');
      DeleteFile('/tmp/nc-test-cmd');
      for i := 0 to l.Count - 1 do
      begin
        TLog('> ' + l[i]);
        try Run(l[i]); except on E: Exception do TLog('error: ' + E.Message); end;
      end;
    except on E: Exception do TLog('error: ' + E.Message); end;
  finally
    l.Free;
  end;
end;

initialization
  if GetEnvironmentVariable('NCAMP_TEST_DRIVER') = '1' then
  begin
    GDriver := TNcTestDriver.alloc.init;
    NSTimer.scheduledTimerWithTimeInterval_target_selector_userInfo_repeats(0.25, GDriver, objcselector('tick:'), nil, True);
  end;
end.
