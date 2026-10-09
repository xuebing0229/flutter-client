#!/usr/bin/env bash
# Identical PP-OCRv5 mobile model assets as the standalone Android ncnn implementation.
# Validate the Git object hash so a changed remote asset cannot silently enter a build.
set -euo pipefail
base=https://raw.githubusercontent.com/equationl/ncnn-android-ppocrv5/9414502728d4bd23395fa4aa6e026f1e04f6c1f5/app/src/main/assets
mkdir -p android/app/src/main/assets
while read -r name sha; do
  path="android/app/src/main/assets/$name"
  if [[ ! -f "$path" || "$(git hash-object "$path")" != "$sha" ]]; then
    curl --fail --location --retry 4 --retry-delay 2 --output "$path.tmp" "$base/$name"
    [[ "$(git hash-object "$path.tmp")" == "$sha" ]] || { echo "Invalid OCR model: $name" >&2; exit 1; }
    mv "$path.tmp" "$path"
  fi
  echo "Verified $name"
done <<'MODELS'
PP_OCRv5_mobile_det.ncnn.bin 18b2c3d27dec3b5eb7e3f31f6011fbb0036ec81f
PP_OCRv5_mobile_det.ncnn.param eae40ed0d9ac8bda7a6da4fcba4673cfd1386f29
PP_OCRv5_mobile_rec.ncnn.bin 2cf896a1fa1d19615f8bfe8e7831331f94254ffd
PP_OCRv5_mobile_rec.ncnn.param 99adde23549c9577bf85a7b3780d47ecdeec4544
MODELS
