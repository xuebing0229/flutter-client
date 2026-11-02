$ErrorActionPreference = "Stop"

$binary = Resolve-Path "build/windows/x64/runner/Release/syncthing/syncthing.exe"
$tempRoot = Join-Path $env:RUNNER_TEMP ("ag-syncthing-smoke-" + [Guid]::NewGuid().ToString("N"))
$profileHome = Join-Path $tempRoot "home"
$folderPath = Join-Path $tempRoot "folder"
New-Item -ItemType Directory -Force -Path $profileHome, $folderPath | Out-Null

$listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$listener.Start()
$port = ([System.Net.IPEndPoint]$listener.LocalEndpoint).Port
$listener.Stop()

$apiKey = ([Guid]::NewGuid().ToString("N") + [Guid]::NewGuid().ToString("N"))
$baseUrl = "http://127.0.0.1:$port"
$headers = @{ "X-API-Key" = $apiKey }
$folderId = "ag-smoke-" + [Guid]::NewGuid().ToString("N")
$process = $null

function Invoke-SyncthingJson {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null
    )

    $params = @{
        Method = $Method
        Uri = "$baseUrl$Path"
        Headers = $headers
        TimeoutSec = 8
    }
    if ($null -ne $Body) {
        $params["ContentType"] = "application/json"
        $params["Body"] = ($Body | ConvertTo-Json -Depth 32 -Compress)
    } elseif ($Method -in @("POST", "PUT", "PATCH")) {
        $params["ContentType"] = "application/json"
        $params["Body"] = ""
    }
    return Invoke-RestMethod @params
}

try {
    $arguments = @(
        "--home", $profileHome,
        "--gui-address", "127.0.0.1:$port",
        "--gui-apikey", $apiKey,
        "--no-browser",
        "--no-console",
        "--no-restart",
        "--no-upgrade"
    )
    $process = Start-Process -FilePath $binary -ArgumentList $arguments -PassThru -WindowStyle Hidden

    $ready = $false
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if ($process.HasExited) {
            throw "Syncthing exited before REST became ready (exit $($process.ExitCode))."
        }
        try {
            $ping = Invoke-SyncthingJson -Method "GET" -Path "/rest/system/ping"
            if ($ping.ping -eq "pong") {
                $ready = $true
                break
            }
        } catch {
            Start-Sleep -Milliseconds 200
        }
    }
    if (-not $ready) {
        throw "Syncthing REST did not become ready within 30 seconds."
    }

    $system = Invoke-SyncthingJson -Method "GET" -Path "/rest/system/status"
    if ([string]::IsNullOrWhiteSpace($system.myID)) {
        throw "Syncthing did not expose a device ID."
    }

    $foldersBefore = @(Invoke-SyncthingJson -Method "GET" -Path "/rest/config/folders")
    $defaultFolders = @($foldersBefore | Where-Object { $_.id -eq "default" })
    if ($defaultFolders.Count -gt 1) {
        throw "Fresh profile contains more than one default folder."
    }
    if ($defaultFolders.Count -eq 1) {
        Invoke-SyncthingJson -Method "DELETE" -Path "/rest/config/folders/default" | Out-Null
    }
    $foldersAfterPolicy = @(Invoke-SyncthingJson -Method "GET" -Path "/rest/config/folders")
    if ($foldersAfterPolicy | Where-Object { $_.id -eq "default" }) {
        throw "Default folder cleanup through REST did not apply."
    }

    $folder = Invoke-SyncthingJson -Method "GET" -Path "/rest/config/defaults/folder"
    $folder.id = $folderId
    $folder.label = "Adventurers Guild smoke test"
    $folder.path = $folderPath
    $folder.type = "sendreceive"
    $folder.devices = @()
    Invoke-SyncthingJson -Method "POST" -Path "/rest/config/folders" -Body $folder | Out-Null

    $configured = @(Invoke-SyncthingJson -Method "GET" -Path "/rest/config/folders")
    if (-not ($configured | Where-Object { $_.id -eq $folderId })) {
        throw "Folder POST returned but the folder is not present in live config."
    }

    Invoke-SyncthingJson -Method "POST" -Path "/rest/db/scan?folder=$folderId" | Out-Null
    $status = Invoke-SyncthingJson -Method "GET" -Path "/rest/db/status?folder=$folderId"
    if ([string]::IsNullOrWhiteSpace($status.state)) {
        throw "Configured folder has no runtime state."
    }

    Invoke-SyncthingJson -Method "PATCH" -Path "/rest/config/folders/$folderId" -Body @{ paused = $true } | Out-Null
    $paused = Invoke-SyncthingJson -Method "GET" -Path "/rest/config/folders/$folderId"
    if ($paused.paused -ne $true) {
        throw "Folder pause did not apply."
    }

    Invoke-SyncthingJson -Method "PATCH" -Path "/rest/config/folders/$folderId" -Body @{ paused = $false } | Out-Null
    Invoke-SyncthingJson -Method "POST" -Path "/rest/db/scan?folder=$folderId" | Out-Null

    Invoke-SyncthingJson -Method "DELETE" -Path "/rest/config/folders/$folderId" | Out-Null
    $foldersAfter = @(Invoke-SyncthingJson -Method "GET" -Path "/rest/config/folders")
    if ($foldersAfter | Where-Object { $_.id -eq $folderId }) {
        throw "Folder DELETE returned but the folder still exists."
    }

    Invoke-SyncthingJson -Method "POST" -Path "/rest/system/shutdown" | Out-Null
    $exitDeadline = (Get-Date).AddSeconds(10)
    while (-not $process.HasExited -and (Get-Date) -lt $exitDeadline) {
        Start-Sleep -Milliseconds 100
        $process.Refresh()
    }
    if (-not $process.HasExited) {
        throw "Syncthing did not exit after /rest/system/shutdown."
    }

    Write-Host "Syncthing runtime smoke test passed."
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -Path $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
