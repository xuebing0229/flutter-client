# Official PaddleOCR PP-OCRv6 Android single-engine implementation

Only one Android OCR engine: official PP-OCRv6 Tiny via the standalone
Android SDK imported from PaddlePaddle/PaddleOCR at commit
`dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf`:
https://github.com/PaddlePaddle/PaddleOCR/tree/dab3fe35379033fdcb2d0e9572fac0b36c9a9ebf/deploy/ppocr-android

Android SDK Kotlin sources under `android/ppocr-sdk/src/main/` are **verbatim**
upstream sources. The small `ppocr-sdk/build.gradle.kts` changes only the
Gradle host integration (AGP9) and replaces an older, Android-linker-incompatible
OpenCV AAR with `org.opencv:opencv:4.13.0` (same Java/OpenCV APIs).
The Flutter native bridge calls the official demo's `OpenCVUtils.init`,
`PaddleOCR.create` and `recognize(bytes)` directly.

Models: official **PP-OCRv6 Tiny** ONNX models fetched *at build time* from
official PaddlePaddle model archives and packaged inside the APK. No online
OCR or runtime download. No ncnn, ML Kit, old third-party paddle_ocr_native,
dual-engine comparisons, local crop retries or crash-marker fallbacks.

The app's order parsing, editing, sync and Windows OCR are not changed.
The native CI test loads both actual ONNX models and recognizes rendered
Chinese and English on a full Android screenshot-size bitmap.

Tests on the emulator prove SDK execution on the emulator only. Real
arm64 phone crash and MiHuashi small-label accuracy require a device check.
