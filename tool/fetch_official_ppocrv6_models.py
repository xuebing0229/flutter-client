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
# SHA256 of the official PaddlePaddle archives' extracted model files.
# Checked on GitHub Actions against the actual downloaded bytes.
EXPECTED_SHA256 = {
    ("det", "inference.onnx"): "193bab7a04fca699a6c82e6abb5b81bdb28177f0abd4062552b04908dafb19f8",
    ("rec", "inference.onnx"): "9ef676d6ed3c88256a2d92c640c44f25b0c40947e111b14b8be8f594091563e6",
    ("rec", "inference.yml"): "66170210bad538e83fff3c4a3867e547d6bf20b50d64b20347c4b913f3034ea1",
}

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
                digest = hashlib.sha256(content).hexdigest()
                if digest != EXPECTED_SHA256[(group, name)]:
                    raise RuntimeError(f"PP-OCRv6 model checksum mismatch: {path}: {digest}")
                print(f"official PP-OCRv6 Tiny: {path} ({len(content)} bytes), sha256={digest}")

if __name__ == "__main__":
    main()
