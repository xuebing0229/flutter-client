#!/usr/bin/env python3
"""Finalize the Adventurers Guild PWA build and offline cache."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

PRECACHE_TOKEN = "__PWA_PRECACHE_FILES__"
CACHE_TOKEN = "__PWA_CACHE_VERSION__"
BOOT_TOKEN = "__PWA_BOOT_VERSION__"
EXCLUDED = {"pwa_service_worker.js", "flutter_service_worker.js"}
BOOT_FILES = ("index.html", "flutter_bootstrap.js")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("build_dir", type=Path)
    args = parser.parse_args()

    root = args.build_dir.resolve()
    worker = root / "pwa_service_worker.js"
    if not worker.is_file():
        raise SystemExit("pwa_service_worker.js is missing from the web build")

    version_path = root / "version.json"
    if not version_path.is_file():
        raise SystemExit("version.json is missing from the web build")
    try:
        version_data = json.loads(version_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as error:
        raise SystemExit(f"version.json is invalid: {error}") from error

    build_number = str(version_data.get("build_number") or "").strip()
    if not build_number.isdigit():
        raise SystemExit("version.json build_number is missing or invalid")

    for name in BOOT_FILES:
        path = root / name
        if not path.is_file():
            raise SystemExit(f"{name} is missing from the web build")
        source = path.read_text(encoding="utf-8")
        if BOOT_TOKEN not in source:
            raise SystemExit(f"{name} is missing the PWA boot-version token")
        path.write_text(
            source.replace(BOOT_TOKEN, build_number),
            encoding="utf-8",
        )

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
    if PRECACHE_TOKEN not in source:
        raise SystemExit("PWA precache token is missing from service worker")
    if CACHE_TOKEN not in source:
        raise SystemExit("PWA cache-version token is missing from service worker")

    digest = hashlib.sha256()
    for rel in files:
        path = root / rel.removeprefix("./")
        digest.update(rel.encode("utf-8"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
        digest.update(b"\0")
    cache_version = (
        f"adventurers-guild-pwa-{build_number}-{digest.hexdigest()[:12]}"
    )

    rendered = source.replace(CACHE_TOKEN, cache_version, 1)
    rendered = rendered.replace(
        PRECACHE_TOKEN,
        json.dumps(files, ensure_ascii=False, separators=(",", ":")),
        1,
    )
    worker.write_text(rendered, encoding="utf-8")

    for name in BOOT_FILES:
        if BOOT_TOKEN in (root / name).read_text(encoding="utf-8"):
            raise SystemExit(f"{name} still contains the PWA boot-version token")

    print(
        f"Finalized PWA build {build_number}, cache {cache_version} "
        f"with {len(files)} files."
    )


if __name__ == "__main__":
    main()
