#!/usr/bin/env python3
"""Finalize the Adventurers Guild PWA service worker with a complete precache list."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

TOKEN = "__PWA_PRECACHE_FILES__"
EXCLUDED = {"pwa_service_worker.js"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("build_dir", type=Path)
    args = parser.parse_args()

    root = args.build_dir.resolve()
    worker = root / "pwa_service_worker.js"
    if not worker.is_file():
        raise SystemExit("pwa_service_worker.js is missing from the web build")

    files: list[str] = []
    for path in sorted(root.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(root).as_posix()
        if rel in EXCLUDED or rel.startswith("."):
            continue
        files.append("./" + rel)

    required = {
        "./index.html",
        "./manifest.json",
        "./flutter_bootstrap.js",
        "./main.dart.js",
    }
    missing = sorted(required.difference(files))
    if missing:
        raise SystemExit("PWA build is missing required files: " + ", ".join(missing))

    source = worker.read_text(encoding="utf-8")
    if TOKEN not in source:
        raise SystemExit("PWA precache token is missing from service worker")

    rendered = source.replace(
        TOKEN,
        json.dumps(files, ensure_ascii=False, separators=(",", ":")),
        1,
    )
    worker.write_text(rendered, encoding="utf-8")
    print(f"Finalized PWA precache with {len(files)} files.")


if __name__ == "__main__":
    main()
