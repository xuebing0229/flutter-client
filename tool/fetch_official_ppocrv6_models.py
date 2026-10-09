#!/usr/bin/env python3
"""Bundle the official PaddleOCR Android PP-OCRv6 Tiny ONNX model files.

Use official PaddlePaddle model archives. All file I/O happens at BUILD TIME.
APK inference is offline. No arbitrary tar extraction or executable content.
"""
import hashlib
import pathlib
import tarfile
import tempfile
import urllib.request

BASE = ("https://paddle-model-ecology.bj.bcebos.com/paddlex/"
        "official_inference_model/paddle3.0.0/")
DEST = pathlib.Path("android/app/src/main/assets/models")
NAMES = {
    "det": "PP-OCRv6_tiny_det_onnx_infer.tar",
    "rec": "PP-OCRv6_tiny_rec_onnx_infer.tar",
}
REQUIRED = {"det": ("inference.onnx",), "rec": ("inference.onnx", "inference.yml")}

def download(url: str, target: pathlib.Path):
    req = urllib.request.Request(url, headers={"User-Agent": "PaddleOCR-Android-model-bundle/1.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=140) as incoming, target.open("wb") as out:
                while chunk := incoming.read(1024 * 1024):
                    out.write(chunk)
            return
        except Exception:
            target.unlink(missing_ok=True)
            if attempt == 2:
                raise
            import time
            time.sleep(3)

def main():
    DEST.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="official-ppocrv6-") as td:
        for group, archive_name in NAMES.items():
            folder = DEST / group
            folder.mkdir(exist_ok=True)
            required = REQUIRED[group]
            if all((folder / f).is_file() and (folder / f).stat().st_size > 100 for f in required):
                print(f"PP-OCRv6 {group} model already present")
                continue
            archive = pathlib.Path(td) / archive_name
            download(BASE + archive_name, archive)
            with tarfile.open(archive, "r:*") as contents:
                for name in required:
                    candidates = [m for m in contents.getmembers()
                                  if m.isfile() and pathlib.PurePosixPath(m.name).name == name]
                    if len(candidates) != 1:
                        raise RuntimeError(f"{archive_name}: expected one {name}, got {len(candidates)}")
                    with contents.extractfile(candidates[0]) as data:
                        out = folder / name
                        with out.open("wb") as output:
                            while chunk := data.read(1024 * 1024):
                                output.write(chunk)
        for group, required in REQUIRED.items():
            for name in required:
                path = DEST / group / name
                content = path.read_bytes()
                assert len(content) > (50_000 if name.endswith(".onnx") else 100)
                if name.endswith(".yml"):
                    assert b"PostProcess:" in content and b"character_dict:" in content
                print(f"official PP-OCRv6 Tiny: {path} ({len(content)} bytes), sha256={hashlib.sha256(content).hexdigest()}")

if __name__ == "__main__":
    main()
