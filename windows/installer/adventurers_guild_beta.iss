#ifndef MyAppVersion
  #define MyAppVersion "0.0.1"
#endif

#define MyAppName "冒险者公会 Beta"
#define MyAppExeName "adventurers_guild.exe"

[Setup]
AppId={{8E886A0E-6E19-4E6F-9A26-0F39E7E7A2C4}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher=xuebing0229
DefaultDirName={localappdata}\Programs\AdventurersGuildBeta
DefaultGroupName=冒险者公会 Beta
DisableProgramGroupPage=yes
DisableDirPage=no
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputBaseFilename=app-windows-beta-setup
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
Name: "{autoprograms}\冒险者公会 Beta"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon_{#MyAppVersion}.ico"
Name: "{autoprograms}\卸载冒险者公会 Beta"; Filename: "{uninstallexe}"
Name: "{autodesktop}\冒险者公会 Beta"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon_{#MyAppVersion}.ico"; Tasks: desktopicon

[InstallDelete]
Type: files; Name: "{autodesktop}\冒险者公会 Beta.lnk"; Tasks: desktopicon
Type: files; Name: "{autoprograms}\冒险者公会 Beta.lnk"
Type: files; Name: "{app}\app_icon_*.ico"

[Run]
Filename: "{sys}\WindowsPowerShell\v1.0\powershell.exe"; Parameters: "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\refresh_app_shortcuts.ps1"" -ExePath ""{app}\{#MyAppExeName}"""; Flags: runhidden; StatusMsg: "正在刷新应用快捷方式和图标…"
Filename: "{app}\{#MyAppExeName}"; Description: "启动冒险者公会 Beta"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"


[Code]
var
  RemoveUserDataOnUninstall: Boolean;

function StopEmbeddedSyncthingForInstall(var ResultCode: Integer): Boolean;
var
  PowerShellPath, InstallDir, Command, Parameters: String;
begin
  Result := False;
  ResultCode := -1;
  PowerShellPath := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  if not FileExists(PowerShellPath) then
    Exit;

  InstallDir := ExpandConstant('{app}');
  Command :=
    '$target = [IO.Path]::GetFullPath(''' + InstallDir +
    '\syncthing\syncthing.exe''); ' +
    '$deadline = (Get-Date).AddSeconds(15); ' +
    'do { ' +
    '$running = @(Get-Process -Name ''syncthing'' -ErrorAction SilentlyContinue | ' +
    'Where-Object { $_.Path -and [IO.Path]::GetFullPath($_.Path).Equals($target, [StringComparison]::OrdinalIgnoreCase) }); ' +
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
  if not StopEmbeddedSyncthingForInstall(ResultCode) then
    Result := '无法在安装前关闭内置同步核心。请关闭冒险者公会后重试。';
end;

function InitializeUninstall(): Boolean;
var
  Choice: Integer;
begin
  Choice := MsgBox(
    '是否同时删除这台电脑上的冒险者公会账号、排单、成品、同步数据和设置？' + #13#10 + #13#10 +
    '选择“否”只卸载程序，数据会保留，之后重新安装仍可继续使用。',
    mbConfirmation,
    MB_YESNO
  );
  RemoveUserDataOnUninstall := Choice = IDYES;
  Result := True;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  SupportDir: String;
  UpdateDir: String;
begin
  if (CurUninstallStep = usPostUninstall) and RemoveUserDataOnUninstall then
  begin
    SupportDir := ExpandConstant('{userappdata}\com.workspace.client\Adventurers Guild');
    DelTree(SupportDir, True, True, True);

    UpdateDir := GetEnv('USERPROFILE') + '\Downloads\AdventurersGuild';
    if UpdateDir <> '\Downloads\AdventurersGuild' then
      DelTree(UpdateDir, True, True, True);
  end;
end;

