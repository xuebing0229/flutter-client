param(
  [string]$OutputDir = "build/windows/x64/runner/Release",
  [string]$CacheDir = ""
)

$ErrorActionPreference = "Stop"
$PaddleOcrCommit = "dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf"
$PaddleInferenceVersion = "3.2.1"
$OpenCvVersion = "4.12.0"
$PaddleInferenceUrl = "https://paddle-inference-lib.bj.bcebos.com/3.2.1/cxx_c/Windows/CPU/x86-64_avx-mkl-vs2019/paddle_inference.zip"
$OpenCvUrl = "https://github.com/opencv/opencv/releases/download/4.12.0/opencv-4.12.0-windows.exe"
$DetModelUrl = "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_det_infer.tar"
$RecModelUrl = "https://paddle-model-ecology.bj.bcebos.com/paddlex/official_inference_model/paddle3.0.0/PP-OCRv6_small_rec_infer.tar"
$DirentUrl = "https://raw.githubusercontent.com/tronkko/dirent/1.26/include/dirent.h"

if (-not $CacheDir) {
  if ($env:RUNNER_TEMP) {
    $CacheDir = Join-Path $env:RUNNER_TEMP "ag-official-paddleocr"
  } else {
    $CacheDir = Join-Path $env:TEMP "ag-official-paddleocr"
  }
}

$runtimeCache = Join-Path $CacheDir "runtime-$PaddleOcrCommit-paddle-$PaddleInferenceVersion-opencv-$OpenCvVersion"
$target = Join-Path $OutputDir "paddleocr"

function Get-File([string]$Url, [string]$Path) {
  if (Test-Path $Path) { return }
  New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null
  Write-Host "Downloading $Url"
  Invoke-WebRequest -UseBasicParsing -Uri $Url -OutFile $Path
}

function Copy-Dlls([string]$Root, [string]$Destination) {
  if (-not (Test-Path $Root)) { return }
  Get-ChildItem -LiteralPath $Root -Recurse -File -Filter "*.dll" | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Force
  }
}

if (-not (Test-Path (Join-Path $runtimeCache "ppocr.exe"))) {
  New-Item -ItemType Directory -Force -Path $CacheDir | Out-Null

  $src = Join-Path $CacheDir "PaddleOCR-$PaddleOcrCommit"
  if (-not (Test-Path (Join-Path $src ".git"))) {
    if (Test-Path $src) { Remove-Item -Recurse -Force $src }
    git clone --filter=blob:none --no-checkout https://github.com/PaddlePaddle/PaddleOCR.git $src
    if ($LASTEXITCODE -ne 0) { throw "Failed to clone official PaddleOCR." }
  }
  git -C $src fetch --depth 1 origin $PaddleOcrCommit
  if ($LASTEXITCODE -ne 0) { throw "Failed to fetch pinned PaddleOCR commit." }
  git -C $src checkout --detach $PaddleOcrCommit
  if ($LASTEXITCODE -ne 0) { throw "Failed to checkout pinned PaddleOCR commit." }

  $downloads = Join-Path $CacheDir "downloads"
  $paddleZip = Join-Path $downloads "paddle_inference_$PaddleInferenceVersion.zip"
  $opencvExe = Join-Path $downloads "opencv-$OpenCvVersion-windows.exe"
  $detTar = Join-Path $downloads "PP-OCRv6_small_det_infer.tar"
  $recTar = Join-Path $downloads "PP-OCRv6_small_rec_infer.tar"

  Get-File $PaddleInferenceUrl $paddleZip
  Get-File $OpenCvUrl $opencvExe
  Get-File $DetModelUrl $detTar
  Get-File $RecModelUrl $recTar

  $paddleExtract = Join-Path $CacheDir "paddle-inference-$PaddleInferenceVersion"
  if (-not (Test-Path $paddleExtract)) {
    Expand-Archive -LiteralPath $paddleZip -DestinationPath $paddleExtract -Force
  }
  $paddleRoot = Get-ChildItem -LiteralPath $paddleExtract -Directory -Recurse |
    Where-Object { Test-Path (Join-Path $_.FullName "paddle\include") } |
    Select-Object -First 1
  if (-not $paddleRoot) { throw "Official Paddle Inference package layout was not recognized." }
  $paddleRoot = $paddleRoot.FullName

  $sevenZip = "C:\Program Files\7-Zip\7z.exe"
  if (-not (Test-Path $sevenZip)) {
    $cmd = Get-Command 7z -ErrorAction SilentlyContinue
    if ($cmd) { $sevenZip = $cmd.Source }
  }
  if (-not (Test-Path $sevenZip)) { throw "7-Zip is required to unpack official OpenCV." }

  $opencvExtract = Join-Path $CacheDir "opencv-$OpenCvVersion"
  if (-not (Test-Path $opencvExtract)) {
    New-Item -ItemType Directory -Force -Path $opencvExtract | Out-Null
    & $sevenZip x $opencvExe "-o$opencvExtract" -y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "OpenCV extraction failed." }
  }
  $opencvBuild = Get-ChildItem -LiteralPath $opencvExtract -Directory -Recurse |
    Where-Object { Test-Path (Join-Path $_.FullName "x64\vc16\lib") } |
    Select-Object -First 1
  if (-not $opencvBuild) { throw "Official OpenCV Windows package layout was not recognized." }
  $opencvBuild = $opencvBuild.FullName

  $cppInfer = Join-Path $src "deploy\cpp_infer"
  Get-File $DirentUrl (Join-Path $cppInfer "dirent.h")

  $build = Join-Path $CacheDir "cpp-build-$PaddleOcrCommit"
  & cmake -S $cppInfer -B $build -A x64 "-DPADDLE_LIB=$paddleRoot" "-DOPENCV_DIR=$opencvBuild" -DWITH_GPU=OFF -DWITH_MKL=ON -DWITH_STATIC_LIB=ON -DUSE_FREETYPE=OFF
  if ($LASTEXITCODE -ne 0) { throw "Official PaddleOCR C++ configure failed." }

  & cmake --build $build --config Release --target ppocr --parallel 2
  if ($LASTEXITCODE -ne 0) { throw "Official PaddleOCR C++ build failed." }

  $ppocr = Get-ChildItem -LiteralPath $build -Recurse -File -Filter "ppocr.exe" |
    Where-Object { $_.FullName -match "\\Release\\" } |
    Select-Object -First 1
  if (-not $ppocr) { throw "Official PaddleOCR ppocr.exe was not created." }

  if (Test-Path $runtimeCache) { Remove-Item -Recurse -Force $runtimeCache }
  New-Item -ItemType Directory -Force -Path $runtimeCache | Out-Null
  Copy-Item -LiteralPath $ppocr.FullName -Destination (Join-Path $runtimeCache "ppocr.exe") -Force
  Copy-Dlls (Split-Path $ppocr.FullName) $runtimeCache
  Copy-Dlls (Join-Path $paddleRoot "paddle") $runtimeCache
  Copy-Dlls (Join-Path $paddleRoot "third_party") $runtimeCache
  Copy-Dlls $build $runtimeCache

  $opencvDll = Get-ChildItem -LiteralPath $opencvBuild -Recurse -File -Filter "opencv_world*.dll" | Select-Object -First 1
  if (-not $opencvDll) { throw "OpenCV runtime DLL was not found." }
  Copy-Item -LiteralPath $opencvDll.FullName -Destination $runtimeCache -Force

  $models = Join-Path $runtimeCache "models"
  New-Item -ItemType Directory -Force -Path $models | Out-Null
  foreach ($model in @(
    @{ Tar = $detTar; Name = "PP-OCRv6_small_det_infer" },
    @{ Tar = $recTar; Name = "PP-OCRv6_small_rec_infer" }
  )) {
    $modelRoot = Join-Path $models $model.Name
    if (Test-Path $modelRoot) { Remove-Item -Recurse -Force $modelRoot }
    $unpack = Join-Path $CacheDir ("unpack-" + $model.Name)
    if (Test-Path $unpack) { Remove-Item -Recurse -Force $unpack }
    New-Item -ItemType Directory -Force -Path $unpack | Out-Null
    tar -xf $model.Tar -C $unpack
    if ($LASTEXITCODE -ne 0) { throw "Failed to unpack model." }
    $source = Get-ChildItem -LiteralPath $unpack -Directory -Recurse |
      Where-Object { $_.Name -eq $model.Name } |
      Select-Object -First 1
    if (-not $source) { throw "Extracted model directory was not found." }
    Copy-Item -LiteralPath $source.FullName -Destination $modelRoot -Recurse -Force
  }

  Copy-Item -LiteralPath (Join-Path $src "LICENSE") -Destination (Join-Path $runtimeCache "LICENSE-PaddleOCR.txt") -Force

  @{
    engine = "PaddleOCR official C++"
    paddleOcrCommit = $PaddleOcrCommit
    paddleInference = $PaddleInferenceVersion
    detector = "PP-OCRv6_small_det"
    recognizer = "PP-OCRv6_small_rec"
    networkRequiredAtRuntime = $false
  } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $runtimeCache "runtime.json") -Encoding UTF8
}

if (Test-Path $target) { Remove-Item -Recurse -Force $target }
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
Copy-Item -LiteralPath $runtimeCache -Destination $target -Recurse -Force

$engine = Join-Path $target "ppocr.exe"
$det = Join-Path $target "models\PP-OCRv6_small_det_infer"
$rec = Join-Path $target "models\PP-OCRv6_small_rec_infer"
if (-not (Test-Path $engine) -or -not (Test-Path $det) -or -not (Test-Path $rec)) {
  throw "Official Windows PaddleOCR bundle is incomplete."
}

Write-Host "Bundled official PaddleOCR C++ + Paddle Inference + PP-OCRv6 Small under $target"
