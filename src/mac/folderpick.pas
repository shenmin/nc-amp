{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit FolderPick;
{ Multi-folder picker (macOS): NSOpenPanel choosing directories, with multiple selection. }
{$mode objfpc}{$H+}
{$modeswitch objectivec1}

interface

uses Classes, SysUtils, LCLType;

{ Shows the dialog. Result: number of folders added to Folders (UTF-8), 0 if the user
  cancelled, -1 if it is not available (caller falls back). Owner is not needed on macOS. }
function PickFolders(Owner: HWND; const Title: string; Folders: TStrings): Integer;

implementation

uses CocoaAll;

function PickFolders(Owner: HWND; const Title: string; Folders: TStrings): Integer;
var
  panel: NSOpenPanel;
  urls: NSArray;
  i: Integer;
  u: NSURL;
begin
  panel := NSOpenPanel.openPanel;
  if panel = nil then Exit(-1);
  panel.setCanChooseFiles(False);
  panel.setCanChooseDirectories(True);
  panel.setAllowsMultipleSelection(True);
  panel.setCanCreateDirectories(False);
  panel.setMessage(NSSTR(PChar(Title)));
  panel.setPrompt(NSSTR('Add'));
  NSApplication.sharedApplication.activateIgnoringOtherApps(True);
  Result := 0;
  if panel.runModal <> NSModalResponseOK then Exit;
  urls := panel.URLs;
  if urls = nil then Exit;
  for i := 0 to urls.count - 1 do
  begin
    u := NSURL(urls.objectAtIndex(i));
    if (u <> nil) and (u.path <> nil) then
    begin
      Folders.Add(string(u.path.UTF8String));
      Inc(Result);
    end;
  end;
end;

end.
