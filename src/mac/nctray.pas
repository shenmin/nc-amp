{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit NcTray;
{ Menu bar status item (macOS) in place of the Windows notification-area icon: an NSStatusItem
  with the app icon. Left click -> OnClick; right click (or control-click) -> OnMenu with the
  screen point below the item (LCL screen coordinates, y down). Same interface as the
  Windows unit, plus the helpers MainForm expects from it. }
{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses Classes, SysUtils, LCLType;

type
  TTrayClickEvent = procedure of object;
  TTrayMenuEvent = procedure(X, Y: Integer) of object;
  TTrayLogEvent = procedure(const s: string) of object;

  TNcTray = class
  private
    FTip: string;
    FAdded: Boolean;
    procedure Log(const s: string);
  public
    OnClick: TTrayClickEvent;
    OnMenu: TTrayMenuEvent;
    OnLog: TTrayLogEvent;
    constructor Create(const Tip: string);
    destructor Destroy; override;
    procedure Show;
    procedure SetTip(const s: string);
  end;

{ the Windows build creates a hidden window to own a tray menu; not needed here }
function CreateMenuOwner(X, Y: Integer): HWND;
function WindowDpi(h: HWND): Integer;
function ThreadAwarenessName: string;

implementation

uses CocoaAll, NcMac;

type
  TNcStatusTarget = objcclass(NSObject)
    procedure ncStatusClicked(sender: id); message 'ncStatusClicked:';
  end;

var
  GTray: TNcTray = nil;
  GItem: NSStatusItem = nil;
  GTarget: TNcStatusTarget = nil;

function CreateMenuOwner(X, Y: Integer): HWND;
begin
  Result := 0;
end;

function WindowDpi(h: HWND): Integer;
begin
  Result := 96;
end;

function ThreadAwarenessName: string;
begin
  Result := 'n/a (macOS)';
end;

procedure TNcStatusTarget.ncStatusClicked(sender: id);
var
  ev: NSEvent;
  right: Boolean;
  fr: NSRect;
  screenH: Double;
begin
  if GTray = nil then Exit;
  ev := NSApplication.sharedApplication.currentEvent;
  right := (ev <> nil) and ((ev.type_ = NSRightMouseUp) or
    ((ev.type_ = NSLeftMouseUp) and ((ev.modifierFlags and NSControlKeyMask) <> 0)));
  GTray.Log('status item clicked, right=' + BoolToStr(right, True));
  if right then
  begin
    if Assigned(GTray.OnMenu) then
    begin
      fr := GItem.button.window.frame;
      screenH := NSScreen.screens.objectAtIndex(0).frame.size.height;
      { bottom-left of the item, in LCL screen coordinates (origin top-left) }
      GTray.OnMenu(Round(fr.origin.x), Round(screenH - fr.origin.y));
    end;
  end
  else if Assigned(GTray.OnClick) then GTray.OnClick();
end;

constructor TNcTray.Create(const Tip: string);
begin
  inherited Create;
  GTray := Self;
  FTip := Tip;
end;

destructor TNcTray.Destroy;
begin
  if GItem <> nil then
  begin
    NSStatusBar.systemStatusBar.removeStatusItem(GItem);
    GItem.release;
    GItem := nil;
  end;
  if GTarget <> nil then begin GTarget.release; GTarget := nil; end;
  GTray := nil;
  inherited Destroy;
end;

procedure TNcTray.Log(const s: string);
begin
  if Assigned(OnLog) then OnLog(s);
end;

procedure TNcTray.Show;
var
  img: NSImage;
  path: string;
begin
  if FAdded then Exit;
  GItem := NSStatusBar.systemStatusBar.statusItemWithLength(NSVariableStatusItemLength);
  GItem.retain;
  GTarget := TNcStatusTarget.alloc.init;
  path := MacResourcePath('nc-amp.icns');
  img := nil;
  if path <> '' then img := NSImage.alloc.initWithContentsOfFile(NSSTR(PChar(path)));
  if img = nil then img := NSApplication.sharedApplication.applicationIconImage;
  if img <> nil then
  begin
    img := img.copy;
    img.setSize(NSMakeSize(18, 18));
    GItem.button.setImage(img);
  end
  else
    GItem.button.setTitle(NSSTR('nc'));
  GItem.button.setTarget(GTarget);
  GItem.button.setAction(objcselector('ncStatusClicked:'));
  GItem.button.sendActionOn(NSLeftMouseUpMask or NSRightMouseUpMask);
  GItem.button.setToolTip(NSSTR(PChar(FTip)));
  FAdded := True;
  Log('status item added, icon=' + BoolToStr(img <> nil, True));
end;

procedure TNcTray.SetTip(const s: string);
begin
  FTip := s;
  if FAdded and (GItem <> nil) then GItem.button.setToolTip(NSSTR(PChar(s)));
end;

end.
