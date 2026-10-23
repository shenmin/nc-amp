{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcMac;
{ macOS helpers shared by the platform units: the Retina backing scale of a window,
  application activation, privately registering the bundled LCD font, the app bundle's
  Resources folder, and notifications for sleep / power-off / quit (to save the playback
  state). Only built on macOS (src/mac). }
{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses Classes, SysUtils, Forms, Graphics;

{ pixels per point of the screen the window is on (2 on Retina); 1 if unknown }
function BackingScaleOf(F: TCustomForm): Double;
{ no font smoothing for the text drawn into this canvas: macOS' smoothing thickens the strokes, which makes
  the Plex Mono LCD text much heavier than on Windows and next to the thin seven-segment digits }
procedure MacLightText(c: TCanvas);
function MacAppActive: Boolean;
procedure MacActivateApp;
{ <bundle>/Contents/Resources/ (or, when run from the source tree, <repo>/assets/...) }
function MacResourcePath(const FileName: string): string;
{ registers a font file shipped with the app for this process only; returns the first of
  Candidates the system knows afterwards (a family / full / PostScript name), or '' }
function MacRegisterBundledFont(const FileName: string; const Candidates: array of string): string;
{ OnEvent is called (on the main thread) before the system sleeps, powers off, or the app quits }
procedure MacObserveShutdown(OnEvent: TNotifyEvent);

implementation

uses CocoaAll, MacOSAll, CocoaGDIObjects, NcTest;   { NcTest: inert unless NCAMP_TEST_DRIVER=1 }

function BackingScaleOf(F: TCustomForm): Double;
var
  v: NSView;
begin
  Result := 1;
  { test driver: render as if on a Retina display (NCAMP_TEST_SCALE=2) to check the 2x paths on a 1x screen }
  if GetEnvironmentVariable('NCAMP_TEST_DRIVER') = '1' then
  begin
    Result := StrToFloatDef(GetEnvironmentVariable('NCAMP_TEST_SCALE'), 0);
    if Result >= 1 then Exit;
    Result := 1;
  end;
  try
    if (F <> nil) and F.HandleAllocated then
    begin
      v := NSView(F.Handle);
      if (v <> nil) and (v.window <> nil) then
      begin
        Result := v.window.backingScaleFactor;
        Exit;
      end;
    end;
    if NSScreen.mainScreen <> nil then Result := NSScreen.mainScreen.backingScaleFactor;
  except
    Result := 1;
  end;
  if Result < 1 then Result := 1;
end;

procedure MacLightText(c: TCanvas);
begin
  CGContextSetShouldSmoothFonts(TCocoaContext(c.Handle).CGContext, 0);
end;

function MacAppActive: Boolean;
begin
  Result := NSApplication.sharedApplication.isActive;
end;

procedure MacActivateApp;
begin
  NSApplication.sharedApplication.activateIgnoringOtherApps(True);
end;

function MacResourcePath(const FileName: string): string;
var
  b: NSBundle;
  p: string;
begin
  Result := '';
  b := NSBundle.mainBundle;
  if (b <> nil) and (b.resourcePath <> nil) then
  begin
    p := IncludeTrailingPathDelimiter(string(b.resourcePath.UTF8String)) + FileName;
    if FileExists(p) then Exit(p);
  end;
  { running the bare executable from the source tree / build dir }
  p := ExtractFilePath(ParamStr(0));
  for p in [p + FileName, p + '../assets/fonts/' + FileName, p + '../../assets/fonts/' + FileName,
            p + '../../../assets/fonts/' + FileName, p + '../../../../assets/fonts/' + FileName] do
    if FileExists(p) then Exit(ExpandFileName(p));
end;

function MacRegisterBundledFont(const FileName: string; const Candidates: array of string): string;
var
  path: string;
  url: CFURLRef;
  err: CFErrorRef;
  i: Integer;
  f: NSFont;
begin
  Result := '';
  path := MacResourcePath(FileName);
  if path = '' then Exit;
  url := CFURLCreateFromFileSystemRepresentation(nil, PChar(path), Length(path), False);
  if url = nil then Exit;
  err := nil;
  CTFontManagerRegisterFontsForURL(url, kCTFontManagerScopeProcess, err);
  CFRelease(url);
  for i := 0 to High(Candidates) do
  begin
    f := NSFont.fontWithName_size(NSSTR(PChar(Candidates[i])), 12);
    if f <> nil then Exit(Candidates[i]);
  end;
end;

type
  TNcObserver = objcclass(NSObject)
    procedure ncNotify(n: NSNotification); message 'ncNotify:';
  end;

var
  GObserver: TNcObserver = nil;
  GOnEvent: TNotifyEvent = nil;

procedure TNcObserver.ncNotify(n: NSNotification);
begin
  if Assigned(GOnEvent) then GOnEvent(nil);
end;

procedure MacObserveShutdown(OnEvent: TNotifyEvent);
begin
  GOnEvent := OnEvent;
  if GObserver <> nil then Exit;
  GObserver := TNcObserver.alloc.init;
  NSWorkspace.sharedWorkspace.notificationCenter.addObserver_selector_name_object(
    GObserver, objcselector('ncNotify:'), NSWorkspaceWillSleepNotification, nil);
  NSWorkspace.sharedWorkspace.notificationCenter.addObserver_selector_name_object(
    GObserver, objcselector('ncNotify:'), NSWorkspaceWillPowerOffNotification, nil);
  NSNotificationCenter.defaultCenter.addObserver_selector_name_object(
    GObserver, objcselector('ncNotify:'), NSApplicationWillTerminateNotification, nil);
end;

end.
