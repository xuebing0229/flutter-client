import 'dart:convert';
import 'dart:io';

import '../sync/windows_syncthing_transport.dart';

class WindowsSelfUpdateLauncher {
  const WindowsSelfUpdateLauncher();

  Future<String> launch({required File archive}) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows self updater can only run on Windows.');
    }

    final executable = File(Platform.resolvedExecutable);
    final installDirectory = executable.parent;
    final executableName = executable.path.split(Platform.pathSeparator).last;
    final workDirectory = archive.parent;

    await _ensureInstallDirectoryWritable(installDirectory);

    // The embedded transport is a separate detached process. Closing the
    // Flutter window does not stop it, so release its executable before the
    // updater tries to replace the installation directory.
    await WindowsSyncthingTransport.instance.shutdown();

    final script = File(
      '${workDirectory.path}${Platform.pathSeparator}apply-windows-update.ps1',
    );
    // Windows PowerShell 5.1 treats a BOM-less script as the current ANSI
    // code page.  The updater contains localized messages, so write an
    // explicit UTF-8 BOM; PowerShell 5.1 and 7 both select UTF-8 reliably.
    await script.writeAsBytes(<int>[
      0xEF,
      0xBB,
      0xBF,
      ...utf8.encode(_powerShellScript),
    ], flush: true);

    // On Windows, Dart's detached mode can be terminated with the parent
    // process when the application exits immediately after spawning it.
    // The updater must stay attached long enough to replace the installation,
    // so use the normal mode and then hand control to the script.
    await Process.start('powershell.exe', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-WindowStyle',
      'Hidden',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
      '-ParentPid',
      pid.toString(),
      '-ArchivePath',
      archive.path,
      '-InstallDir',
      installDirectory.path,
      '-ExeName',
      executableName,
      '-SyncthingPath',
      File(
        '${installDirectory.path}${Platform.pathSeparator}'
        'syncthing${Platform.pathSeparator}syncthing.exe',
      ).path,
    ], mode: ProcessStartMode.normal);

    await Future<void>.delayed(const Duration(milliseconds: 350));
    exit(0);
  }

  Future<void> _ensureInstallDirectoryWritable(Directory directory) async {
    final probe = File(
      '${directory.path}${Platform.pathSeparator}'
      '.adventurers-guild-update-probe-${pid.toString()}',
    );

    try {
      await probe.writeAsString('update-probe', flush: true);
    } on FileSystemException catch (error) {
      throw FileSystemException(
        '当前程序目录不可写，无法自动覆盖更新。请把程序放到有写入权限的目录后重试。',
        directory.path,
        error.osError,
      );
    } finally {
      if (await probe.exists()) {
        try {
          await probe.delete();
        } catch (_) {
          // Best-effort cleanup only.
        }
      }
    }
  }
}

const String _powerShellScript = r'''
param(
  [Parameter(Mandatory = $true)][int]$ParentPid,
  [Parameter(Mandatory = $true)][string]$ArchivePath,
  [Parameter(Mandatory = $true)][string]$InstallDir,
  [Parameter(Mandatory = $true)][string]$ExeName,
  [Parameter(Mandatory = $true)][string]$SyncthingPath
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$WorkRoot = Split-Path -Parent $ArchivePath
$LogPath = Join-Path $WorkRoot 'windows-update.log'
$StageDir = Join-Path $WorkRoot ('stage-' + [Guid]::NewGuid().ToString('N'))
$BackupDir = Join-Path $WorkRoot ('backup-' + [Guid]::NewGuid().ToString('N'))

function Write-UpdateLog {
  param([string]$Message)
  $Line = ('{0:yyyy-MM-dd HH:mm:ss.fff} {1}' -f (Get-Date), $Message)
  Add-Content -LiteralPath $LogPath -Value $Line -Encoding UTF8
}


function Refresh-AppShortcuts {
  param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$InstallDir,
    [Parameter(Mandatory = $false)][string]$IconPath
  )

  try {
    if ([string]::IsNullOrWhiteSpace($IconPath) -or
        -not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
      $IconPath = Get-ChildItem -LiteralPath $InstallDir -Filter 'app_icon_*.ico' -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -ExpandProperty FullName -First 1
    }
    if ([string]::IsNullOrWhiteSpace($IconPath) -or
        -not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
      $IconPath = Join-Path $InstallDir 'app_icon.ico'
    }
    if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
      $IconPath = $ExePath
    }

    $Shell = New-Object -ComObject WScript.Shell
    $Candidates = @(
      (Join-Path ([Environment]::GetFolderPath('Programs')) '冒险者公会 Beta.lnk'),
      (Join-Path ([Environment]::GetFolderPath('Desktop')) '冒险者公会 Beta.lnk')
    )

    $PinnedRoot = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    if (Test-Path -LiteralPath $PinnedRoot -PathType Container) {
      $Candidates += Get-ChildItem -LiteralPath $PinnedRoot -Filter '*.lnk' -File |
        Select-Object -ExpandProperty FullName
    }

    foreach ($ShortcutPath in ($Candidates | Select-Object -Unique)) {
      if (-not (Test-Path -LiteralPath $ShortcutPath -PathType Leaf)) {
        continue
      }

      try {
        $Shortcut = $Shell.CreateShortcut($ShortcutPath)
        if ([string]::IsNullOrWhiteSpace($Shortcut.TargetPath)) {
          continue
        }

        $ShortcutTarget = [IO.Path]::GetFullPath($Shortcut.TargetPath)
        $ExpectedTarget = [IO.Path]::GetFullPath($ExePath)
        if (-not $ShortcutTarget.Equals(
          $ExpectedTarget,
          [StringComparison]::OrdinalIgnoreCase
        )) {
          continue
        }

        $Shortcut.IconLocation = $IconPath + ',0'
        $Shortcut.WorkingDirectory = $InstallDir
        $Shortcut.Save()
      } catch {
        Write-UpdateLog ("Shortcut refresh skipped: " + $_.Exception.Message)
      }
    }

    try {
      Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AdventurersGuildShellRefresh {
  [DllImport("shell32.dll")]
  public static extern void SHChangeNotify(
    uint wEventId,
    uint uFlags,
    IntPtr dwItem1,
    IntPtr dwItem2
  );
}
'@
      [AdventurersGuildShellRefresh]::SHChangeNotify(
        0x08000000,
        0,
        [IntPtr]::Zero,
        [IntPtr]::Zero
      )
    } catch {
      Write-UpdateLog ("Shell icon refresh skipped: " + $_.Exception.Message)
    }
  } catch {
    Write-UpdateLog ("Shortcut refresh failed: " + $_.Exception.Message)
  }
}

function Restore-Backup {
  if (-not (Test-Path -LiteralPath $BackupDir)) {
    return
  }

  Write-UpdateLog 'Restoring previous application files.'
  Get-ChildItem -LiteralPath $BackupDir -Force | ForEach-Object {
    $Destination = Join-Path $InstallDir $_.Name
    if ($_.PSIsContainer) {
      if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
      }
      Copy-Item -LiteralPath $_.FullName -Destination $InstallDir -Recurse -Force
    } else {
      Copy-Item -LiteralPath $_.FullName -Destination $Destination -Force
    }
  }
}

function Get-EmbeddedSyncthingProcesses {
  if (-not (Test-Path -LiteralPath $SyncthingPath -PathType Leaf)) {
    return @()
  }

  $ExpectedPath = [IO.Path]::GetFullPath($SyncthingPath)
  @(Get-Process -Name 'syncthing' -ErrorAction SilentlyContinue |
    Where-Object {
      try {
        $ProcessPath = $_.Path
        $ProcessPath -and
          [IO.Path]::GetFullPath($ProcessPath).Equals(
            $ExpectedPath,
            [StringComparison]::OrdinalIgnoreCase
          )
      } catch {
        $false
      }
    })
}

function Stop-EmbeddedSyncthing {
  $Deadline = (Get-Date).AddSeconds(15)
  while ($true) {
    $Processes = @(Get-EmbeddedSyncthingProcesses)
    foreach ($Process in $Processes) {
      try {
        Write-UpdateLog ("Stopping embedded Syncthing process " + $Process.Id + '.')
        Stop-Process -Id $Process.Id -Force -ErrorAction Stop
      } catch {
        if ((Get-Date) -ge $Deadline) {
          throw "无法停止内置同步核心：$($_.Exception.Message)"
        }
      }
    }

    if (@(Get-EmbeddedSyncthingProcesses).Count -eq 0) {
      return
    }
    if ((Get-Date) -ge $Deadline) {
      throw '内置同步核心仍在运行，无法替换 syncthing.exe。'
    }
    Start-Sleep -Milliseconds 250
  }
}

try {
  Write-UpdateLog "Updater started. Parent PID: $ParentPid"

  if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
    throw "Update archive does not exist: $ArchivePath"
  }

  $Deadline = (Get-Date).AddSeconds(90)
  while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
    if ((Get-Date) -ge $Deadline) {
      throw 'The application did not exit within 90 seconds.'
    }
    Start-Sleep -Milliseconds 250
  }

  Stop-EmbeddedSyncthing
  Write-UpdateLog 'Application exited. Extracting update archive.'
  New-Item -ItemType Directory -Path $StageDir -Force | Out-Null
  Expand-Archive -LiteralPath $ArchivePath -DestinationPath $StageDir -Force

  $Executable = Get-ChildItem -LiteralPath $StageDir -Filter $ExeName -File -Recurse |
    Select-Object -First 1

  if ($null -eq $Executable) {
    throw "The update archive does not contain $ExeName."
  }

  $SourceRoot = $Executable.Directory.FullName
  $IconItem = Get-ChildItem -LiteralPath $SourceRoot -Filter 'app_icon_*.ico' -File |
    Select-Object -First 1
  $SourceItems = @(Get-ChildItem -LiteralPath $SourceRoot -Force)

  if ($SourceItems.Count -eq 0) {
    throw 'The extracted update package is empty.'
  }

  Write-UpdateLog 'Backing up files that will be replaced.'
  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null

  foreach ($Item in $SourceItems) {
    $Destination = Join-Path $InstallDir $Item.Name
    if (Test-Path -LiteralPath $Destination) {
      if ($Item.PSIsContainer) {
        Copy-Item -LiteralPath $Destination -Destination $BackupDir -Recurse -Force
      } else {
        Copy-Item -LiteralPath $Destination -Destination (Join-Path $BackupDir $Item.Name) -Force
      }
    }
  }

  Write-UpdateLog 'Applying new application files.'
  foreach ($Item in $SourceItems) {
    $Destination = Join-Path $InstallDir $Item.Name

    if ($Item.PSIsContainer) {
      if (Test-Path -LiteralPath $Destination) {
        Remove-Item -LiteralPath $Destination -Recurse -Force
      }
      Copy-Item -LiteralPath $Item.FullName -Destination $InstallDir -Recurse -Force
    } else {
      Copy-Item -LiteralPath $Item.FullName -Destination $Destination -Force
    }
  }

  $NewExecutable = Join-Path $InstallDir $ExeName
  if (-not (Test-Path -LiteralPath $NewExecutable -PathType Leaf)) {
    throw "Updated executable was not installed: $NewExecutable"
  }

  Write-UpdateLog 'Refreshing shortcuts and shell icon cache.'
  $InstalledIconPath = if ($null -ne $IconItem) {
    Join-Path $InstallDir $IconItem.Name
  } else {
    $null
  }
  Refresh-AppShortcuts -ExePath $NewExecutable -InstallDir $InstallDir -IconPath $InstalledIconPath

  Write-UpdateLog 'Update applied successfully. Restarting application.'
  Start-Process -FilePath $NewExecutable -WorkingDirectory $InstallDir

  Start-Sleep -Milliseconds 750
  Remove-Item -LiteralPath $ArchivePath -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $StageDir -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $BackupDir -Recurse -Force -ErrorAction SilentlyContinue
  Write-UpdateLog 'Update cleanup completed.'
  exit 0
}
catch {
  $Message = $_.Exception.Message
  Write-UpdateLog ("Update failed: " + $Message)

  try {
    Restore-Backup
  } catch {
    Write-UpdateLog ("Rollback failed: " + $_.Exception.Message)
  }

  $ExistingExecutable = Join-Path $InstallDir $ExeName
  if (Test-Path -LiteralPath $ExistingExecutable -PathType Leaf) {
    try {
      Start-Process -FilePath $ExistingExecutable -WorkingDirectory $InstallDir
    } catch {
      Write-UpdateLog ("Could not restart existing application: " + $_.Exception.Message)
    }
  }

  try {
    Add-Type -AssemblyName System.Windows.Forms
    $NL = [Environment]::NewLine
    $DialogMessage = '自动更新失败。' + $NL + $NL + $Message + $NL + $NL + '日志：' + $LogPath
    [System.Windows.Forms.MessageBox]::Show(
      $DialogMessage,
      '冒险者公会更新失败',
      [System.Windows.Forms.MessageBoxButtons]::OK,
      [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
  } catch {
    # The log file remains available even if the message box cannot be shown.
  }

  exit 1
}
''';
