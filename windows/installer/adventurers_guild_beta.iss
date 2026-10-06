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
UninstallDisplayIcon={app}\app_icon.ico
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
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\冒险者公会 Beta"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon.ico"
Name: "{autoprograms}\卸载冒险者公会 Beta"; Filename: "{uninstallexe}"
Name: "{autodesktop}\冒险者公会 Beta"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\app_icon.ico"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "启动冒险者公会 Beta"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}"


[Code]
var
  RemoveUserDataOnUninstall: Boolean;

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
