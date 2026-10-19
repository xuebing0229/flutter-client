from pathlib import Path

root = Path(__file__).resolve().parents[1]
page = (root / "server" / "release_site" / "index.html").read_text(encoding="utf-8")
notes = (root / "server" / "release_site" / "public_notes.txt").read_text(encoding="utf-8").strip()

for token in ("文件校验信息", "SHA-256", "androidSha", "windowsSha"):
    if token in page:
        raise SystemExit(f"Public release page must not expose checksum UI: {token}")

if not notes:
    raise SystemExit("Public release notes must not be empty.")

for token in (
    "GitHub", "服务器", "SHA-256", "签名", "Syncthing", "ACK",
    "tombstone", "原子绑定", "端口", "工作流", "流水线", "构建号",
    "source_test_build",
):
    if token in notes:
        raise SystemExit(f"Public release notes contain implementation detail: {token}")

print("Public release surface guard passed.")
