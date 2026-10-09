# Android screenshot OCR — Beta 117

Android now uses **one** engine only, PP-OCRv5 Mobile via the existing ncnn
Android SDK. No ML Kit fallback, custom ONNX/OpenCV isolate, duplicate local
crop recognition, or dual-engine comparison UI remains.

Reference Android implementation:
https://github.com/equationl/paddleocr4android/tree/master/ncnnAndroidPPOCR

Integration and SDK API documentation:
https://github.com/equationl/paddleocr4android/blob/master/doc/ncnn.md

Native OCR reference app:
https://github.com/nihui/ncnn-android-ppocrv5

The SDK is built by JitPack at version v1.3.0, the four PP-OCRv5 Mobile
model files come from the pinned upstream commit
9414502728d4bd23395fa4aa6e026f1e04f6c1f5 and are SHA-verified
by tool/fetch_ncnn_ocr_models.sh. All inference stays on the phone; no model
files are downloaded at runtime. Windows remains on its Windows-only
RapidOCR engine; unrelated backup/sync, order and product logic are unchanged.

To build Android locally:
bash tool/fetch_ncnn_ocr_models.sh
flutter build apk --release --flavor beta

Unit tests validate parsers; the Android instrumentation test invokes the
real ncnn library with image pixels. Device-specific performance and buyer
name accuracy still require live testing on representative phone screenshots.
