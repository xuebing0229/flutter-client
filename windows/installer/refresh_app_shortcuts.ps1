param(
  [Parameter(Mandatory = $true)][string]$ExePath
)

$ErrorActionPreference = 'Stop'
$ExePath = [IO.Path]::GetFullPath($ExePath)
$InstallDir = Split-Path -Parent $ExePath
$Version = [Diagnostics.FileVersionInfo]::GetVersionInfo($ExePath)
$IconName = 'app_icon_{0}.{1}.{2}+{3}.ico' -f
  $Version.FileMajorPart, $Version.FileMinorPart,
  $Version.FileBuildPart, $Version.FilePrivatePart
$IconPath = Join-Path $InstallDir $IconName

# Changing the icon path prevents Explorer from reusing the previous build's
# cached image. The icon is bundled alongside the executable by the workflow.
if (-not (Test-Path -LiteralPath $IconPath -PathType Leaf)) {
  throw "The package is missing its versioned icon: $IconPath"
}

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class AdventurersGuildShellRefresh {
  [DllImport("shell32.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
  public static extern void SHChangeNotify(
    uint eventId, uint flags, string firstPath, string secondPath
  );
}
'@

$Shell = New-Object -ComObject WScript.Shell
$ShortcutDirectories = @(
  [Environment]::GetFolderPath('Programs'),
  [Environment]::GetFolderPath('Desktop'),
  (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
)

foreach ($Directory in $ShortcutDirectories) {
  if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
    continue
  }

  foreach ($File in (Get-ChildItem -LiteralPath $Directory -Filter '*.lnk' -File)) {
    try {
      $Shortcut = $Shell.CreateShortcut($File.FullName)
      if ([string]::IsNullOrWhiteSpace($Shortcut.TargetPath)) {
        continue
      }
      if (-not [IO.Path]::GetFullPath($Shortcut.TargetPath).Equals(
        $ExePath, [StringComparison]::OrdinalIgnoreCase
      )) {
        continue
      }

      $Shortcut.IconLocation = $IconPath + ',0'
      $Shortcut.WorkingDirectory = $InstallDir
      $Shortcut.Save()
      # SHCNE_UPDATEITEM with SHCNF_PATHW | SHCNF_FLUSH.
      [AdventurersGuildShellRefresh]::SHChangeNotify(
        0x00002000, 0x1005, $File.FullName, $null
      )
      Write-Output ("Refreshed shortcut: " + $File.FullName)
    } catch {
      Write-Warning ("Could not refresh " + $File.FullName + ": " + $_.Exception.Message)
    }
  }
}

[AdventurersGuildShellRefresh]::SHChangeNotify(
  0x00002000, 0x1005, $ExePath, $null
)
# Invalidate the shell image list after replacing the application's resources.
[AdventurersGuildShellRefresh]::SHChangeNotify(
  0x08000000, 0x1000, $null, $null
)
