from pathlib import Path
import re
import sys

root = Path(__file__).resolve().parents[1]
page = (root / "server" / "release_site" / "index.html").read_text(encoding="utf-8")
notes = (root / "server" / "release_site" / "public_notes.txt").read_text(encoding="utf-8").strip()
changelog = (root / "lib" / "core" / "changelog" / "adventurer_news.dart").read_text(encoding="utf-8")

page_forbidden = [
    "文件校验信息",
    "SHA-256",
    "androidSha",
    "windowsSha",
]
for token in page_forbidden:
    if token in page:
        raise SystemExit(f"Public release page must not expose checksum UI: {token}")

if not notes:
    raise SystemExit("Public release notes must not be empty.")

notes_forbidden = [
    "GitHub",
    "服务器",
    "SHA-256",
    "签名",
    "Syncthing",
    "ACK",
    "tombstone",
    "原子绑定",
    "端口",
    "工作流",
    "流水线",
    "构建号",
    "source_test_build",
]
for token in notes_forbidden:
    if token in notes:
        raise SystemExit(f"Public release notes contain implementation detail: {token}")

catalog_marker = "const internalAdventurerNewsCatalog = <AdventurerNewsEntry>["
catalog_start = changelog.find(catalog_marker)
if catalog_start < 0:
    raise SystemExit("Internal Adventurer News catalog was not found.")
catalog_end = changelog.find("\n];", catalog_start)
if catalog_end < 0:
    raise SystemExit("Internal Adventurer News catalog end was not found.")
internal_catalog = changelog[catalog_start:catalog_end]

catalog_forbidden = [
    "GitHub",
    "服务器",
    "SHA-256",
    "Syncthing",
    "ACK",
    "tombstone",
    "原子绑定",
    "source_test_build",
]
for token in catalog_forbidden:
    if token in internal_catalog:
        raise SystemExit(f"Internal Adventurer News contains implementation detail: {token}")

if re.search(r"基于测试版\s*\d+", internal_catalog):
    raise SystemExit("Internal Adventurer News must not expose source test build lineage.")

print("Public release surface guard passed.")
