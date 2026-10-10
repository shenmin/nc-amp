{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit FolderPick;
{ Multi-folder picker: the Windows Vista+ common item dialog (IFileOpenDialog) with
  FOS_PICKFOLDERS or FOS_ALLOWMULTISELECT or FOS_FORCEFILESYSTEM, owned by the player
  window. Interfaces are declared here (minimal, exact vtable order) rather than taken
  from FPC's ShlObj, whose IShellItem.GetDisplayName has a wrong parameter type. }
{$mode objfpc}{$H+}

interface

uses Windows, Classes, SysUtils, ActiveX;

{ Shows the dialog. Result: number of folders added to Folders (UTF-8), 0 if the user
  cancelled, -1 if IFileOpenDialog is not available (caller falls back). }
function PickFolders(Owner: HWND; const Title: string; Folders: TStrings): Integer;

implementation

const
  CLSID_FileOpenDialog: TGUID = '{DC1C5A9C-E88A-4dde-A5A1-60F82A20AEF7}';
  FOS_PICKFOLDERS      = $00000020;
  FOS_FORCEFILESYSTEM  = $00000040;
  FOS_ALLOWMULTISELECT = $00000200;
  FOS_PATHMUSTEXIST    = $00000800;
  SIGDN_FILESYSPATH    = DWORD($80058000);
  ERROR_CANCELLED_HR   = HRESULT($800704C7);

type
  INcShellItem = interface(IUnknown)
    ['{43826d1e-e718-42ee-bc55-a1e261c37bfe}']
    function BindToHandler(pbc: Pointer; const bhid: TGUID; const riid: TGUID; out ppv): HRESULT; stdcall;
    function GetParent(out ppsi: INcShellItem): HRESULT; stdcall;
    function GetDisplayName(sigdnName: DWORD; out ppszName: PWideChar): HRESULT; stdcall;
    function GetAttributes(sfgaoMask: DWORD; out psfgaoAttribs: DWORD): HRESULT; stdcall;
    function Compare(psi: INcShellItem; hint: DWORD; out piOrder: Integer): HRESULT; stdcall;
  end;

  INcShellItemArray = interface(IUnknown)
    ['{b63ea76d-1f85-456f-a19c-48159efa858b}']
    function BindToHandler(pbc: Pointer; const bhid: TGUID; const riid: TGUID; out ppv): HRESULT; stdcall;
    function GetPropertyStore(flags: DWORD; const riid: TGUID; out ppv): HRESULT; stdcall;
    function GetPropertyDescriptionList(keyType: Pointer; const riid: TGUID; out ppv): HRESULT; stdcall;
    function GetAttributes(AttribFlags: DWORD; sfgaoMask: DWORD; out psfgaoAttribs: DWORD): HRESULT; stdcall;
    function GetCount(out pdwNumItems: DWORD): HRESULT; stdcall;
    function GetItemAt(dwIndex: DWORD; out ppsi: INcShellItem): HRESULT; stdcall;
    function EnumItems(out ppenum: IUnknown): HRESULT; stdcall;
  end;

  INcFileOpenDialog = interface(IUnknown)
    ['{d57c7288-d4ad-4768-be02-9d969532d960}']
    { IModalWindow }
    function Show(hwndOwner: HWND): HRESULT; stdcall;
    { IFileDialog }
    function SetFileTypes(cFileTypes: UINT; rgFilterSpec: Pointer): HRESULT; stdcall;
    function SetFileTypeIndex(iFileType: UINT): HRESULT; stdcall;
    function GetFileTypeIndex(out piFileType: UINT): HRESULT; stdcall;
    function Advise(pfde: Pointer; out pdwCookie: DWORD): HRESULT; stdcall;
    function Unadvise(dwCookie: DWORD): HRESULT; stdcall;
    function SetOptions(fos: DWORD): HRESULT; stdcall;
    function GetOptions(out pfos: DWORD): HRESULT; stdcall;
    function SetDefaultFolder(psi: INcShellItem): HRESULT; stdcall;
    function SetFolder(psi: INcShellItem): HRESULT; stdcall;
    function GetFolder(out ppsi: INcShellItem): HRESULT; stdcall;
    function GetCurrentSelection(out ppsi: INcShellItem): HRESULT; stdcall;
    function SetFileName(pszName: PWideChar): HRESULT; stdcall;
    function GetFileName(out pszName: PWideChar): HRESULT; stdcall;
    function SetTitle(pszTitle: PWideChar): HRESULT; stdcall;
    function SetOkButtonLabel(pszText: PWideChar): HRESULT; stdcall;
    function SetFileNameLabel(pszLabel: PWideChar): HRESULT; stdcall;
    function GetResult(out ppsi: INcShellItem): HRESULT; stdcall;
    function AddPlace(psi: INcShellItem; fdap: DWORD): HRESULT; stdcall;
    function SetDefaultExtension(pszDefaultExtension: PWideChar): HRESULT; stdcall;
    function Close(hr: HRESULT): HRESULT; stdcall;
    function SetClientGuid(const guid: TGUID): HRESULT; stdcall;
    function ClearClientData: HRESULT; stdcall;
    function SetFilter(pFilter: Pointer): HRESULT; stdcall;
    { IFileOpenDialog }
    function GetResults(out ppenum: INcShellItemArray): HRESULT; stdcall;
    function GetSelectedItems(out ppsai: INcShellItemArray): HRESULT; stdcall;
  end;

const
  { own client GUID: Windows remembers the last folder of *this* dialog separately }
  NCAMP_FOLDER_DLG: TGUID = '{6E2C3A51-8F0B-4D1C-9A7E-5B3D2C1F0A47}';

function PickFolders(Owner: HWND; const Title: string; Folders: TStrings): Integer;
var
  dlg: INcFileOpenDialog;
  arr: INcShellItemArray;
  item: INcShellItem;
  opts, n, i: DWORD;
  p: PWideChar;
  hr: HRESULT;
  wt: UnicodeString;
begin
  Result := -1;
  if Failed(CoCreateInstance(CLSID_FileOpenDialog, nil, CLSCTX_INPROC_SERVER,
    INcFileOpenDialog, dlg)) or (dlg = nil) then Exit;
  opts := 0;
  dlg.GetOptions(opts);
  if Failed(dlg.SetOptions(opts or FOS_PICKFOLDERS or FOS_ALLOWMULTISELECT or
    FOS_FORCEFILESYSTEM or FOS_PATHMUSTEXIST)) then Exit;
  wt := UTF8Decode(Title);
  dlg.SetTitle(PWideChar(wt));
  dlg.SetClientGuid(NCAMP_FOLDER_DLG);
  hr := dlg.Show(Owner);
  if hr = ERROR_CANCELLED_HR then Exit(0);
  if Failed(hr) then Exit(-1);
  Result := 0;
  if Failed(dlg.GetResults(arr)) or (arr = nil) then Exit;
  n := 0;
  arr.GetCount(n);
  if n > 0 then
    for i := 0 to n - 1 do
      if Succeeded(arr.GetItemAt(i, item)) and (item <> nil) then
      begin
        p := nil;
        if Succeeded(item.GetDisplayName(SIGDN_FILESYSPATH, p)) and (p <> nil) then
        begin
          Folders.Add(UTF8Encode(UnicodeString(p)));
          CoTaskMemFree(p);
          Inc(Result);
        end;
        item := nil;
      end;
end;

end.
