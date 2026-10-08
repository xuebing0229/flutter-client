# Build-time bundling of the offline Windows OCR engine. No user install needed.
param([string]$OutputDir = "build/windows/x64/runner/Release")
$ErrorActionPreference = "Stop"
$target = Join-Path $OutputDir "ocr"
New-Item -Path $target -ItemType Directory -Force | Out-Null

$choices = @(
  "C:\\Program Files\\Tesseract-OCR",
  "C:\\Program Files (x86)\\Tesseract-OCR",
  (Join-Path $env:ChocolateyInstall "lib\\tesseract\\tools")
)
$root = $choices | Where-Object { $_ -and (Test-Path (Join-Path $_ "tesseract.exe")) } | Select-Object -First 1
if (-not $root) {
  choco install tesseract --no-progress -y
  if ($LASTEXITCODE -ne 0) { throw "Unable to install OCR build dependency" }
  $root = $choices | Where-Object { $_ -and (Test-Path (Join-Path $_ "tesseract.exe")) } | Select-Object -First 1
}
if (-not $root) { throw "OCR build dependency not found" }

Copy-Item -LiteralPath (Join-Path $root "tesseract.exe") -Destination $target -Force
Get-ChildItem -LiteralPath $root -File -Filter "*.dll" | Copy-Item -Destination $target -Force
$tessdata = Join-Path $target "tessdata"
New-Item -ItemType Directory -Path $tessdata -Force | Out-Null
foreach ($language in @("chi_sim", "eng")) {
  $model = Join-Path $tessdata "$language.traineddata"
  Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/$language.traineddata" -OutFile $model
  if ((Get-Item $model).Length -lt 200000) { throw "OCR model $language is incomplete" }
}
@'
Tesseract and tessdata_fast are licensed under Apache License 2.0.
https://github.com/tesseract-ocr/tesseract
https://github.com/tesseract-ocr/tessdata_fast
The binaries and data are included for offline image recognition.
'@ | Set-Content -Path (Join-Path $target "README-LICENSE.txt") -Encoding UTF8

& (Join-Path $target "tesseract.exe") --list-langs --tessdata-dir $tessdata
if ($LASTEXITCODE -ne 0) { throw "Bundled OCR engine failed to start" }
Write-Host "Bundled offline Windows OCR under $target"
