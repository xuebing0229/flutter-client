# Run under Windows PowerShell 5.1, the runtime used by the updater and installer.
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$FixtureRoot = Join-Path $PSScriptRoot ('windows-updater-fixture-' + [Guid]::NewGuid().ToString('N'))
$PowerShellPath = Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
$FixtureExe = Join-Path $FixtureRoot 'fixture.exe'

function Assert-Test {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function New-TestInstall {
  param([string]$Name)
  $Root = Join-Path $FixtureRoot $Name
  $Install = Join-Path $Root 'installed app'
  $Work = Join-Path $Root 'updates'
  $Source = Join-Path $Root 'package'
  foreach ($Directory in @($Install, $Work, $Source)) {
    New-Item -ItemType Directory -Path (Join-Path $Directory 'syncthing') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Directory 'data') -Force | Out-Null
  }
  foreach ($Directory in @($Install, $Source)) {
    Copy-Item -LiteralPath $FixtureExe -Destination (Join-Path $Directory 'adventurers_guild.exe')
    Copy-Item -LiteralPath $FixtureExe -Destination (Join-Path $Directory 'syncthing/syncthing.exe')
  }
  [IO.File]::WriteAllText((Join-Path $Install 'data/version.txt'), 'old')
  [IO.File]::WriteAllText((Join-Path $Source 'data/version.txt'), 'new')
  # The shell-shortcut boundary is replaced by a harmless fixture. File and
  # process operations, replacement, rollback and restart are production code.
  [IO.File]::WriteAllText((Join-Path $Source 'refresh_app_shortcuts.ps1'), "param([string]`$ExePath)`nWrite-Output 'Fixture shortcuts refreshed.'")
  $Case = [pscustomobject]@{
    Install = $Install
    Work = $Work
    Source = $Source
    Exe = (Join-Path $Install 'adventurers_guild.exe')
    Syncthing = (Join-Path $Install 'syncthing/syncthing.exe')
    Archive = (Join-Path $Work 'update.zip')
    Log = (Join-Path $Work 'windows-update.log')
  }
  return $Case
}

function Start-Fixture {
  param([string]$Path)
  $Process = Start-Process -FilePath $Path -WorkingDirectory (Split-Path -Parent $Path) -WindowStyle Hidden -PassThru
  Assert-Test (-not $Process.WaitForExit(150)) ('Fixture failed to start: ' + $Path)
  return $Process
}

function Get-FixtureAppProcesses {
  param($Case)
  @(Get-Process -Name 'adventurers_guild' -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path.Equals($Case.Exe, [StringComparison]::OrdinalIgnoreCase) }
    catch { $false }
  })
}

function Invoke-TestUpdater {
  param($Case, [int]$ParentId, [string]$Archive = $Case.Archive)
  & $PowerShellPath -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File $UpdaterPath `
    -ParentPid $ParentId -ArchivePath $Archive -InstallDir $Case.Install `
    -ExeName 'adventurers_guild.exe' -SyncthingPath $Case.Syncthing
  return $LASTEXITCODE
}

New-Item -ItemType Directory -Path $FixtureRoot | Out-Null
try {
  # Small inert executables really hold their image files open on Windows.
  Add-Type -TypeDefinition 'public static class UpdaterFixture { public static void Main() { System.Threading.Thread.Sleep(300000); } }' `
    -OutputAssembly $FixtureExe -OutputType WindowsApplication

  $LauncherPath = Join-Path $RepoRoot 'lib/core/update/windows_self_update_launcher.dart'
  $Launcher = [IO.File]::ReadAllText($LauncherPath)
  $Prefix = "const String _powerShellScript = r'''"
  $Start = $Launcher.IndexOf($Prefix) + $Prefix.Length
  $End = $Launcher.IndexOf("''';", $Start)
  $Updater = $Launcher.Substring($Start, $End - $Start)
  $Tokens = $null
  $Errors = $null
  $Ast = [Management.Automation.Language.Parser]::ParseInput($Updater, [ref]$Tokens, [ref]$Errors)
  Assert-Test ($Errors.Count -eq 0) ($Errors | Out-String)
  $Dialog = $Ast.Find({ param($Node)
    $Node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and
    $Node.Extent.Text.StartsWith('[System.Windows.Forms.MessageBox]::Show(')
  }, $true)
  Assert-Test ($null -ne $Dialog) 'Failure-dialog boundary not found.'
  $Updater = $Updater.Remove($Dialog.Extent.StartOffset, $Dialog.Extent.Text.Length).Insert($Dialog.Extent.StartOffset, '0')
  $UpdaterPath = Join-Path $FixtureRoot 'apply-windows-update.ps1'
  [IO.File]::WriteAllText($UpdaterPath, $Updater, (New-Object Text.UTF8Encoding($true)))

  $Other = New-TestInstall 'other installation'
  $OtherApp = Start-Fixture $Other.Exe
  $OtherSync = Start-Fixture $Other.Syncthing

  $Success = New-TestInstall 'multiple instances'
  $Parent = Start-Fixture $Success.Exe
  $StaleOne = Start-Fixture $Success.Exe
  $StaleTwo = Start-Fixture $Success.Exe
  $Sync = Start-Fixture $Success.Syncthing
  Stop-Process -Id $Parent.Id -Force
  $Parent.WaitForExit()
  Compress-Archive -Path (Join-Path $Success.Source '*') -DestinationPath $Success.Archive
  Assert-Test ((Invoke-TestUpdater $Success $Parent.Id) -eq 0) 'Multi-instance update failed.'
  Assert-Test ($StaleOne.WaitForExit(1000) -and $StaleTwo.WaitForExit(1000) -and $Sync.WaitForExit(1000)) 'Old installation processes still hold files.'
  Assert-Test ((Get-FixtureAppProcesses $Success).Count -eq 1) 'Update did not restart exactly one instance.'
  Assert-Test ([IO.File]::ReadAllText((Join-Path $Success.Install 'data/version.txt')) -eq 'new') 'New files were not installed.'
  Assert-Test (-not (Test-Path -LiteralPath $Success.Archive)) 'Successful update did not remove the consumed archive.'
  Assert-Test (-not $OtherApp.HasExited -and -not $OtherSync.HasExited) 'Another installation was stopped.'
  Write-Output 'PASS: real multi-instance file replacement, scoped process shutdown and one restart.'

  $Failure = New-TestInstall 'failed before shutdown'
  $Remaining = Start-Fixture $Failure.Exe
  Assert-Test ((Invoke-TestUpdater $Failure $Remaining.Id) -eq 1) 'Missing archive should fail.'
  $RemainingProcesses = @(Get-FixtureAppProcesses $Failure)
  Assert-Test ($RemainingProcesses.Count -eq 1 -and $RemainingProcesses[0].Id -eq $Remaining.Id) 'Failure spawned a duplicate application.'
  Assert-Test ([IO.File]::ReadAllText((Join-Path $Failure.Install 'data/version.txt')) -eq 'old') 'Early failure changed installed data.'
  Write-Output 'PASS: failure with a surviving app does not spawn another instance.'

  $Rollback = New-TestInstall 'rollback failure'
  Compress-Archive -Path (Join-Path $Rollback.Source '*') -DestinationPath $Rollback.Archive
  $LockedFile = [IO.File]::Open((Join-Path $Rollback.Install 'data/version.txt'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
  try {
    Assert-Test ((Invoke-TestUpdater $Rollback $Parent.Id) -eq 1) 'Locked file should fail replacement.'
    Assert-Test ((Get-FixtureAppProcesses $Rollback).Count -eq 0) 'Incomplete rollback launched mixed application files.'
    Assert-Test ([IO.File]::ReadAllText($Rollback.Log).Contains('Rollback failed:')) 'Rollback failure was not exercised.'
    Assert-Test (Test-Path -LiteralPath $Rollback.Archive) 'Failed update discarded its recovery archive.'
  } finally {
    $LockedFile.Dispose()
  }
  Write-Output 'PASS: incomplete rollback does not launch a partially replaced installation.'

  # Evaluate the installer command built by the Pascal string literals,
  # substituting only Inno Setup's resolved installation directory and macro.
  $Installer = [IO.File]::ReadAllText((Join-Path $RepoRoot 'windows/installer/adventurers_guild_beta.iss'))
  $CommandSection = [regex]::Match($Installer, '(?s)Command :=\s*(.*?)\s*Parameters :=').Groups[1].Value
  $Install = New-TestInstall "installer's upgrade"
  $InstalledOne = Start-Fixture $Install.Exe
  $InstalledTwo = Start-Fixture $Install.Exe
  $InstalledSync = Start-Fixture $Install.Syncthing
  $Parts = [regex]::Matches($CommandSection, "'(?:[^']|'')*'|\bInstallDir\b")
  $InstallerDirectory = $Install.Install
  if ($Installer.Contains("StringChangeEx(InstallDir, '''', '''''', True);")) {
    $InstallerDirectory = $InstallerDirectory.Replace("'", "''")
  }
  $Command = ($Parts | ForEach-Object {
    if ($_.Value -eq 'InstallDir') { $InstallerDirectory }
    else { $_.Value.Substring(1, $_.Value.Length - 2).Replace("''", "'") }
  }) -join ''
  $Command = $Command.Replace('{#MyAppExeName}', 'adventurers_guild.exe')
  $Encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
  & $PowerShellPath -NoProfile -NonInteractive -WindowStyle Hidden -EncodedCommand $Encoded
  Assert-Test ($LASTEXITCODE -eq 0) 'Installer process shutdown failed.'
  Assert-Test ($InstalledOne.WaitForExit(1000) -and $InstalledTwo.WaitForExit(1000) -and $InstalledSync.WaitForExit(1000)) 'Installer left old processes alive.'
  Assert-Test (-not $OtherApp.HasExited -and -not $OtherSync.HasExited) 'Installer stopped an unrelated installation.'
  Write-Output 'PASS: installer removes stale instances and Syncthing only from its own install directory.'
} finally {
  $ExpectedParent = [IO.Path]::GetFullPath($PSScriptRoot) + [IO.Path]::DirectorySeparatorChar
  $ResolvedFixture = [IO.Path]::GetFullPath($FixtureRoot)
  if (-not $ResolvedFixture.StartsWith($ExpectedParent, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Fixture cleanup target escaped the tool directory.'
  }
  $FixturePrefix = $ResolvedFixture + [IO.Path]::DirectorySeparatorChar
  Get-Process -Name 'adventurers_guild', 'syncthing' -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path.StartsWith($FixturePrefix, [StringComparison]::OrdinalIgnoreCase) }
    catch { $false }
  } | ForEach-Object {
    Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    $_.WaitForExit(1000) | Out-Null
  }
  Remove-Item -LiteralPath $ResolvedFixture -Recurse -Force
}
