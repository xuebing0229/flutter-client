#ifndef MyAppVersion
  #define MyAppVersion "0.1.4"
#endif

#define MyAppName "冒险者公会"
#define MyAppExeName "adventurers_guild.exe"

[Setup]
AppId={{4B17F5BD-B2B4-4FB2-9E60-14D5A5E2B491}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=xuebing0229
DefaultDirName={localappdata}\Programs\AdventurersGuildInternal
DefaultGroupName=冒险者公会
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=app-windows-internal-setup
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\app_icon_{#MyAppVersion}.ico
ChangesAssociations=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes
UsePreviousTasks=yes

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式："; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\app_icon_{#MyAppVersion}.ico"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "app_icon*.ico"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\冒险者公会"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon_{#MyAppVersion}.ico"
Name: "{autoprograms}\卸载冒险者公会"; Filename: "{uninstallexe}"
Name: "{autodesktop}\冒险者公会"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon_{#MyAppVersion}.ico"; Tasks: desktopicon

[InstallDelete]
Type: files; Name: "{autodesktop}\冒险者公会.lnk"; Tasks: desktopicon
Type: files; Name: "{autoprograms}\冒险者公会.lnk"
Type: files; Name: "{app}\app_icon_*.ico"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\refresh_app_shortcuts.ps1"" -ExePath ""{app}\{#MyAppExeName}"""; Flags: runhidden; StatusMsg: "正在刷新应用快捷方式和图标…"
Filename: "{app}\{#MyAppExeName}"; Description: "启动冒险者公会"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"


[Code]
var
  RemoveUserDataOnUninstall: Boolean;

function StopInstalledProcesses(var ResultCode: Integer): Boolean;
var
  PowerShellPath, InstallDir, Command, Parameters: String;
begin
  Result := False;
  ResultCode := -1;
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not FileExists(PowerShellPath) then
    Exit;

  InstallDir := ExpandConstant('{app}');
  StringChangeEx(InstallDir, '''', '''''', True);
  Command :=
    '$targets = @([IO.Path]::GetFullPath(''' + InstallDir +
    '\{#MyAppExeName}''), [IO.Path]::GetFullPath(''' + InstallDir +
    '\syncthing\syncthing.exe''), [IO.Path]::GetFullPath(''' + InstallDir +
    '\desktop_pet\AdventurersGuild.DesktopPet.exe'')); ' +
    '$deadline = (Get-Date).AddSeconds(15); ' +
    'do { ' +
    '$running = @(Get-Process -Name ''adventurers_guild'',''syncthing'',''AdventurersGuild.DesktopPet'' -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -and $targets -contains [IO.Path]::GetFullPath($_.Path) }); ' +
    'if ($running.Count -eq 0) { exit 0 }; ' +
    '$running | Stop-Process -Force -ErrorAction SilentlyContinue; ' +
    'Start-Sleep -Milliseconds 250 ' +
    '} while ((Get-Date) -lt $deadline); exit 1';
  Parameters :=
    '-NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "' +
    Command + '"';
  if not Exec(
    PowerShellPath, Parameters, '', SW_HIDE, ewWaitUntilTerminated, ResultCode
  ) then
    Exit;
  Result := ResultCode = 0;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  Result := '';
  if not StopInstalledProcesses(ResultCode) then
    Result := '无法在安装前关闭旧版冒险者公会、桌宠或内置同步核心。请关闭后重试。';
end;

function InitializeUninstall(): Boolean;
var
  Choice: Integer;
begin
  Choice := MsgBox(
    '是否同时删除这台电脑上的冒险者公会个人数据？' + #13#10 + #13#10 +
    '选择“是”：彻底删除本机账号、排单、成品、同步记录、桌宠素材、截图导入记录和设置。' + #13#10 +
    '选择“否”：只删除程序，个人数据会保留，之后重新安装仍可继续使用。' + #13#10 + #13#10 +
    '你自己导出的备份文件和保存到其他位置的图片不会被删除。',
    mbConfirmation,
    MB_YESNOCANCEL
  );

  if Choice = IDCANCEL then
  begin
    Result := False;
    Exit;
  end;

  RemoveUserDataOnUninstall := Choice = IDYES;
  Result := True;
end;

procedure CleanupManagedUpdateCache();
var
  UserProfile, UpdateRoot, UpdateDir: String;
begin
  UserProfile := GetEnv('USERPROFILE');
  if UserProfile = '' then
    Exit;

  UpdateRoot := UserProfile + '\Downloads\AdventurersGuild';
  UpdateDir := UpdateRoot + '\updates\internal';

  { Only remove the updater-owned subdirectory. Never recursively delete the
    whole AdventurersGuild downloads folder because users may place exported
    backups or other files there themselves. }
  DelTree(UpdateDir, True, True, True);

  { Remove the parent only when it is empty. If the user has anything else in
    it, RemoveDir fails safely and leaves those files untouched. }
  RemoveDir(UpdateRoot);
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  ResultCode: Integer;
  SupportDir: String;
begin
  if CurUninstallStep = usUninstall then
  begin
    if not StopInstalledProcesses(ResultCode) then
    begin
      MsgBox(
        '无法关闭正在运行的冒险者公会、桌宠或内置同步核心。请先关闭后再卸载。',
        mbError,
        MB_OK
      );
      Abort;
    end;
  end;

  if CurUninstallStep = usPostUninstall then
  begin
    CleanupManagedUpdateCache();

    if RemoveUserDataOnUninstall then
    begin
      SupportDir := ExpandConstant(
        '{userappdata}\com.workspace.client.internal\Adventurers Guild Internal'
      );
      DelTree(SupportDir, True, True, True);
    end;
  end;
end;
