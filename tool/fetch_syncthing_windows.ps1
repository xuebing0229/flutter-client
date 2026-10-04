param(
    [string]$Version = "v2.1.5",
    [string]$Destination = ""
)

$ErrorActionPreference = "Stop"

$root = Resolve-Path (Join-Path $PSScriptRoot "..")
if ([string]::IsNullOrWhiteSpace($Destination)) {
    $Destination = Join-Path $root "build\windows\x64\runner\Release\syncthing"
}

$versionWithoutV = $Version.TrimStart("v")
$archiveName = "syncthing-windows-amd64-$Version.zip"
$url = "https://github.com/syncthing/syncthing/releases/download/$Version/$archiveName"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("artist-workbench-syncthing-" + [Guid]::NewGuid().ToString("N"))
$archive = Join-Path $tempRoot $archiveName
$extract = Join-Path $tempRoot "extract"

New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
try {
    Write-Host "Downloading Syncthing $Version for Windows..."
    Invoke-WebRequest -Uri $url -OutFile $archive
    Expand-Archive -Path $archive -DestinationPath $extract -Force

    $binary = Get-ChildItem -Path $extract -Filter "syncthing.exe" -Recurse |
        Select-Object -First 1
    if ($null -eq $binary) {
        throw "syncthing.exe was not found in $archiveName"
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Copy-Item -Path $binary.FullName -Destination (Join-Path $Destination "syncthing.exe") -Force

    $target = Join-Path $Destination "syncthing.exe"
    if (-not (Test-Path $target)) {
        throw "Failed to stage Syncthing at $target"
    }
    Write-Host "Embedded Syncthing ready: $target"
}
finally {
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
