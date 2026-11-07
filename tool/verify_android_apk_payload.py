#!/usr/bin/env python3
"""Fail CI when a built APK is missing native/runtime payloads used by the app."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


KNOWN_ABIS = ("arm64-v8a", "armeabi-v7a", "x86_64")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("apk", type=Path)
    parser.add_argument(
        "--abis",
        nargs="+",
        choices=KNOWN_ABIS,
        default=list(KNOWN_ABIS),
        help="Android ABIs that must be present. Defaults to the legacy universal set.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    apk: Path = args.apk
    expected_abis = tuple(args.abis)

    if not apk.is_file():
        raise SystemExit(f"APK not found: {apk}")

    required = [
        "assets/models/det/inference.onnx",
        "assets/models/rec/inference.onnx",
        "assets/models/rec/inference.yml",
    ]
    for abi in expected_abis:
        required.extend(
            (
                f"lib/{abi}/libsyncthing.so",
                f"lib/{abi}/libonnxruntime.so",
                f"lib/{abi}/libopencv_java4.so",
            )
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

        unexpected_abis = [
            abi
            for abi in KNOWN_ABIS
            if abi not in expected_abis
            and any(name.startswith(f"lib/{abi}/") for name in names)
        ]
        if unexpected_abis:
            raise SystemExit(
                "Android package contains unexpected ABI payloads: "
                + ", ".join(unexpected_abis)
            )

    print(
        "Android runtime payload verified for ABI(s): "
        + ", ".join(expected_abis)
        + "."
    )


if __name__ == "__main__":
    main()
