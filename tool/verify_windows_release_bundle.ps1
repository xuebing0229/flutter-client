param(
  [string]$ReleaseDir = "build/windows/x64/runner/Release"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ReleaseDir)) {
  throw "Windows release directory is missing: $ReleaseDir"
}

$requiredFiles = @(
  "adventurers_guild.exe",
  "flutter_windows.dll",
  "data\icudtl.dat",
  "syncthing\syncthing.exe",
  "desktop_pet\AdventurersGuild.DesktopPet.exe",
  "desktop_pet\AdventurersGuild.DesktopPet.dll",
  "desktop_pet\AdventurersGuild.DesktopPet.deps.json",
  "desktop_pet\AdventurersGuild.DesktopPet.runtimeconfig.json",
  "desktop_pet\coreclr.dll",
  "desktop_pet\hostfxr.dll",
  "desktop_pet\hostpolicy.dll",
  "desktop_pet\LICENSE-VPET.txt",
  "desktop_pet\THIRD_PARTY_NOTICES.txt",
  "paddleocr\ppocr.exe",
  "paddleocr\OCR.yaml",
  "paddleocr\models\PP-OCRv6_small_det_infer\inference.json",
  "paddleocr\models\PP-OCRv6_small_det_infer\inference.pdiparams",
  "paddleocr\models\PP-OCRv6_small_det_infer\inference.yml",
  "paddleocr\models\PP-OCRv6_small_rec_infer\inference.json",
  "paddleocr\models\PP-OCRv6_small_rec_infer\inference.pdiparams",
  "paddleocr\models\PP-OCRv6_small_rec_infer\inference.yml",
  "refresh_app_shortcuts.ps1"
)

foreach ($relative in $requiredFiles) {
  $path = Join-Path $ReleaseDir $relative
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Windows package payload is missing: $relative"
  }
  if ((Get-Item -LiteralPath $path).Length -le 0) {
    throw "Windows package payload is empty: $relative"
  }
}

$flutterAssets = Join-Path $ReleaseDir "data\flutter_assets"
if (-not (Test-Path -LiteralPath $flutterAssets -PathType Container)) {
  throw "Windows package payload is missing Flutter assets."
}

$paddleDlls = @(Get-ChildItem -LiteralPath (Join-Path $ReleaseDir "paddleocr") -File -Filter "*.dll")
if ($paddleDlls.Count -eq 0) {
  throw "Windows PaddleOCR runtime contains no DLLs."
}

$config = Join-Path $ReleaseDir "paddleocr\OCR.yaml"
if (-not (Select-String -LiteralPath $config -Pattern '^pipeline_name:\s*OCR\s*$' -Quiet)) {
  throw "Windows PaddleOCR OCR.yaml is invalid."
}

Write-Host "Windows runtime payload verified: Flutter, Syncthing, desktop pet and PaddleOCR are present."
