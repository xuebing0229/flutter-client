# Android OCR: official PaddleOCR baseline

This branch deliberately removes our OCR-engine tuning and uses the official
PaddlePaddle Android demo path as the baseline.

Upstream reference revision:
https://github.com/PaddlePaddle/PaddleOCR/tree/dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf/deploy/ppocr-android

The vendored `ppocr-sdk/src/main` source remains upstream PaddleOCR source.
The engine is initialized exactly like the official `OCRApplication.loadModels()`:

```kotlin
OpenCVUtils.init(context)
PaddleOCR.create(
    context = context,
    config = PaddleOCRConfig(
        recScoreThresh = 0.0f,
        recBatchSize = 1,
    ),
)
```

Recognition follows the official ViewModel path: read the encoded image bytes
and call `ocr.recognize(bytes)`.

Official runtime dependency versions are restored:
- ONNX Runtime Android 1.21.1
- QuickBird OpenCV Android 4.5.3
- kotlinx-coroutines-android 1.9.0
- AndroidX core-ktx 1.15.0

The only app-specific layers left around the engine are:
1. the Flutter MethodChannel transport;
2. mapping OCR result boxes back to Dart;
3. explicit release after an import batch, because this app does not need OCR
   to remain resident outside screenshot import;
4. local crash diagnostics, which do not alter model inference.

We still bundle PP-OCRv6 Small in the SDK's default asset paths
`models/det/inference.onnx`, `models/rec/inference.onnx`, and
`models/rec/inference.yml`. No custom detector limits, thread count, model
paths, preprocessing, postprocessing, or fallback OCR are configured.

This baseline is intentionally boring: if it crashes on the real ARM64 phone,
the next step is to compare the native tombstone against the standalone
official demo, not to invent more OCR changes.
