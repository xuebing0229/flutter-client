#!/usr/bin/env python3
"""Prepare sqlite3 .dump output for Cloudflare D1 import."""

from __future__ import annotations

import argparse
from pathlib import Path


def transform(text: str) -> str:
    lines = text.splitlines()
    out: list[str] = []
    skipping_cf_kv = False
    for line in lines:
        stripped = line.strip()
        upper = stripped.upper()
        if upper in {"BEGIN TRANSACTION;", "COMMIT;"}:
            continue
        if stripped.startswith("CREATE TABLE _cf_KV"):
            skipping_cf_kv = True
            if stripped.endswith(";"):
                skipping_cf_kv = False
            continue
        if skipping_cf_kv:
            if stripped.endswith(";"):
                skipping_cf_kv = False
            continue
        if stripped.startswith('INSERT INTO "_cf_KV"') or stripped.startswith("INSERT INTO _cf_KV"):
            continue
        out.append(line)
    return "\n".join(out).rstrip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.write_text(
        transform(args.input.read_text(encoding="utf-8")),
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
