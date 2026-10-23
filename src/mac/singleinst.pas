{ SPDX-License-Identifier: GPL-3.0-or-later
  Copyright (C) 2026 Shen Min }
unit SingleInst;
{ One nc-amp per user session (macOS).
  - IsPrimaryInstance: an advisory lock (flock) on ~/Library/Application Support/nc-amp/nc-amp.lock.
    A second instance forwards its command-line paths over the first instance's Unix domain
    socket (/tmp/nc-amp-<uid>.sock) - retrying ~2 s while the first one is still starting -
    and returns False so the program exits before any window or status item exists.
    (Opening files with Finder / `open` never starts a second instance: LaunchServices hands
    them to the running one as an "open files" event, see MainForm.)
  - StartIpcServer: the first instance's listener thread; requests are delivered on the main
    thread. Same interface as the Windows unit. }
{$mode objfpc}{$H+}

interface

uses Classes, SysUtils;

type
  TIpcEvent = procedure(Paths: TStrings) of object;   { empty list = just activate }

function IsPrimaryInstance: Boolean;
procedure StartIpcServer(OnRequest: TIpcEvent);
procedure StopIpcServer;

implementation

uses BaseUnix, Unix, Sockets;

var
  GLockFd: cint = -1;
  GOnRequest: TIpcEvent = nil;
  GSock: cint = -1;
  GThread: TThread = nil;
  GStop: Boolean = False;

procedure Log(const s: string);
var
  fn: string;
  f: TextFile;
begin
  fn := GetEnvironmentVariable('NCAMP_LOG');
  if fn = '' then Exit;
  try
    AssignFile(f, fn);
    if FileExists(fn) then Append(f) else Rewrite(f);
    WriteLn(f, FormatDateTime('hh:nn:ss.zzz', Now), ' [pid ', GetProcessID, '] ', s);
    CloseFile(f);
  except
  end;
end;

function SockPath: string;
begin
  Result := '/tmp/nc-amp-' + IntToStr(fpGetUID) + '.sock';
end;

function LockPath: string;
var
  d: string;
begin
  d := GetEnvironmentVariable('HOME');
  if d <> '' then d := IncludeTrailingPathDelimiter(d) + 'Library/Application Support/nc-amp/'
  else d := '/tmp/';
  ForceDirectories(d);
  Result := d + 'nc-amp.lock';
end;

function ConnectTo(out fd: cint): Boolean;
var
  addr: sockaddr_un;
  p: string;
begin
  Result := False;
  fd := fpSocket(AF_UNIX, SOCK_STREAM, 0);
  if fd < 0 then Exit;
  FillChar(addr, SizeOf(addr), 0);
  addr.sun_family := AF_UNIX;
  p := SockPath;
  Move(p[1], addr.sun_path[0], Length(p));
  Result := fpConnect(fd, @addr, SizeOf(addr)) = 0;
  if not Result then begin fpClose(fd); fd := -1; end;
end;

function IsPrimaryInstance: Boolean;
var
  i, tries: Integer;
  fd: cint;
  payload, p: string;
begin
  GLockFd := fpOpen(PChar(LockPath), O_RDWR or O_CREAT, &600);
  if GLockFd >= 0 then
  begin
    if fpFlock(GLockFd, LOCK_EX or LOCK_NB) = 0 then Exit(True);   { we are the one }
  end
  else
    Exit(True);   { cannot lock: do not refuse to start }
  { second instance: absolute paths (relative to OUR working directory), one per line }
  payload := '';
  for i := 1 to ParamCount do
  begin
    p := ParamStr(i);
    if (p = '') or (Copy(p, 1, 5) = '-psn_') then Continue;
    p := ExpandFileName(p);
    Log('second instance arg: ' + p);
    payload := payload + p + #10;
  end;
  { the first instance may still be starting: wait up to ~2 s for its socket }
  fd := -1;
  for tries := 1 to 40 do
  begin
    if ConnectTo(fd) then Break;
    Sleep(50);
  end;
  Log(Format('second instance: %d path(s), connected=%s after %d tries', [ParamCount, BoolToStr(fd >= 0, True), tries]));
  if fd >= 0 then
  begin
    if payload = '' then payload := #10;   { "just activate" }
    fpWrite(fd, payload[1], Length(payload));
    fpShutdown(fd, 1);
    fpClose(fd);
    Log('forwarded');
  end;
  Result := False;                     { exit: one instance only }
end;

type
  TIpcThread = class(TThread)
  private
    FPaths: TStringList;
    procedure Deliver;
  protected
    procedure Execute; override;
  end;

procedure TIpcThread.Deliver;
begin
  Log(Format('ipc: received %d path(s)', [FPaths.Count]));
  if Assigned(GOnRequest) then GOnRequest(FPaths);   { must copy what it needs }
end;

procedure TIpcThread.Execute;
var
  cl: cint;
  buf: array[0..4095] of Char;
  n: ssize_t;
  data: string;
  pfd: pollfd;
  i, st: Integer;
begin
  while not GStop do
  begin
    pfd.fd := GSock; pfd.events := POLLIN; pfd.revents := 0;
    if fpPoll(@pfd, 1, 200) <= 0 then Continue;
    cl := fpAccept(GSock, nil, nil);
    if cl < 0 then Continue;
    data := '';
    repeat
      n := fpRead(cl, buf[0], SizeOf(buf));
      if n > 0 then
      begin
        SetLength(data, Length(data) + n);
        Move(buf[0], data[Length(data) - n + 1], n);
      end;
    until n <= 0;
    fpClose(cl);
    FPaths := TStringList.Create;
    try
      st := 1;
      for i := 1 to Length(data) do
        if data[i] = #10 then
        begin
          if i > st then FPaths.Add(Copy(data, st, i - st));
          st := i + 1;
        end;
      Synchronize(@Deliver);
    finally
      FreeAndNil(FPaths);
    end;
  end;
end;

procedure StartIpcServer(OnRequest: TIpcEvent);
var
  addr: sockaddr_un;
  p: string;
begin
  GOnRequest := OnRequest;
  if GSock >= 0 then Exit;
  GSock := fpSocket(AF_UNIX, SOCK_STREAM, 0);
  if GSock < 0 then Exit;
  p := SockPath;
  fpUnlink(PChar(p));        { stale socket of an earlier run: we hold the lock, so nobody else listens }
  FillChar(addr, SizeOf(addr), 0);
  addr.sun_family := AF_UNIX;
  Move(p[1], addr.sun_path[0], Length(p));
  if (fpBind(GSock, @addr, SizeOf(addr)) <> 0) or (fpListen(GSock, 4) <> 0) then
  begin
    Log('ipc server: cannot listen on ' + p);
    fpClose(GSock); GSock := -1;
    Exit;
  end;
  fpChmod(PChar(p), &600);
  GStop := False;
  GThread := TIpcThread.Create(False);
  Log('ipc server listening on ' + p);
end;

procedure StopIpcServer;
begin
  GOnRequest := nil;
  GStop := True;
  if GThread <> nil then
  begin
    GThread.WaitFor;
    FreeAndNil(GThread);
  end;
  if GSock >= 0 then
  begin
    fpClose(GSock); GSock := -1;
    fpUnlink(PChar(SockPath));
  end;
end;

finalization
  if GLockFd >= 0 then fpClose(GLockFd);
end.
