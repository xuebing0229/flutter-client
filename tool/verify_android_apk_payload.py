#!/usr/bin/env python3
"""Fail CI when a built APK is missing native/runtime payloads used by the app."""

from __future__ import annotations

import sys
import zipfile
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: verify_android_apk_payload.py <apk>")

    apk = Path(sys.argv[1])
    if not apk.is_file():
        raise SystemExit(f"APK not found: {apk}")

    required = (
        "assets/models/det/inference.onnx",
        "assets/models/rec/inference.onnx",
        "assets/models/rec/inference.yml",
        "lib/arm64-v8a/libsyncthing.so",
        "lib/armeabi-v7a/libsyncthing.so",
        "lib/x86_64/libsyncthing.so",
        "lib/arm64-v8a/libonnxruntime.so",
        "lib/arm64-v8a/libopencv_java4.so",
    )

    with zipfile.ZipFile(apk) as package:
        names = set(package.namelist())
        missing = [name for name in required if name not in names]
        if missing:
            raise SystemExit(
                "Android package payload is incomplete; missing: "
                + ", ".join(missing)
            )
        empty = [name for name in required if package.getinfo(name).file_size <= 0]
        if empty:
            raise SystemExit(
                "Android package payload contains empty files: "
                + ", ".join(empty)
            )

    print("Android runtime payload verified: OCR and embedded Syncthing are present.")


if __name__ == "__main__":
    main()
