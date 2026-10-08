# Ship RapidOcrOnnx + PP-OCRv3 models with the app; zero end-user installs.
param([string]$OutputDir = "build/windows/x64/runner/Release")
$ErrorActionPreference = "Stop"
$version = "1.2.2"
$target = Join-Path $OutputDir "rapidocr"
$modelsTarget = Join-Path $target "models"
New-Item -Path $modelsTarget -ItemType Directory -Force | Out-Null

$sevenZip = "C:\\Program Files\\7-Zip\\7z.exe"
if (-not (Test-Path $sevenZip)) {
  $sevenZip = (Get-Command 7z -ErrorAction SilentlyContinue).Source
}
if (-not $sevenZip) { throw "7-Zip is required on the Windows build runner." }

$cache = Join-Path $env:RUNNER_TEMP "ag-rapidocr-build"
New-Item -Path $cache -ItemType Directory -Force | Out-Null
$binArchive = Join-Path $cache "windows-bin.7z"
$projectArchive = Join-Path $cache "project.7z"
Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/RapidAI/RapidOcrOnnx/releases/download/$version/windows-bin.7z" -OutFile $binArchive
Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/RapidAI/RapidOcrOnnx/releases/download/$version/Project_RapidOcrOnnx-$version.7z" -OutFile $projectArchive

$binDir = Join-Path $cache "binary"
$projDir = Join-Path $cache "project"
& $sevenZip x $binArchive "-o$binDir" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "RapidOCR binary extraction failed" }
& $sevenZip x $projectArchive "-o$projDir" -y | Out-Null
if ($LASTEXITCODE -ne 0) { throw "RapidOCR model extraction failed" }

$executable = Get-ChildItem -LiteralPath $binDir -Filter "RapidOcrOnnx.exe" -File -Recurse |
  Where-Object { $_.FullName -match 'CPU.x64' -or $_.FullName -match 'x64' } |
  Select-Object -First 1
if (-not $executable) { throw "RapidOcrOnnx x64 executable not found." }
Copy-Item -LiteralPath $executable.FullName -Destination (Join-Path $target "RapidOcrOnnx.exe") -Force
Get-ChildItem -LiteralPath $executable.Directory.FullName -File -Filter "*.dll" |
  Copy-Item -Destination $target -Force

foreach ($model in @(
  "ch_PP-OCRv3_det_infer.onnx",
  "ch_ppocr_mobile_v2.0_cls_infer.onnx",
  "ch_PP-OCRv3_rec_infer.onnx",
  "ppocr_keys_v1.txt"
)) {
  $match = Get-ChildItem -LiteralPath $projDir -Recurse -File -Filter $model |
    Select-Object -First 1
  if (-not $match) { throw "RapidOCR model file not found: $model" }
  Copy-Item -LiteralPath $match.FullName -Destination (Join-Path $modelsTarget $model) -Force
}
Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/RapidAI/RapidOcrOnnx/main/LICENSE" -OutFile (Join-Path $target "LICENSE-RapidOcrOnnx.txt")

& (Join-Path $target "RapidOcrOnnx.exe") --version
if ($LASTEXITCODE -ne 0) { throw "Bundled RapidOCR binary failed to start." }
Write-Host "Bundled self-contained PP-OCR ONNX Chinese recognition under $target"
