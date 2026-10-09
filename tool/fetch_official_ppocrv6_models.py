#!/usr/bin/env python3
"""Bundle the official PaddleOCR Android PP-OCRv6 Small ONNX model files.

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
    "det": "PP-OCRv6_small_det_onnx_infer.tar",
    "rec": "PP-OCRv6_small_rec_onnx_infer.tar",
}
REQUIRED = {"det": ("inference.onnx",), "rec": ("inference.onnx", "inference.yml")}
# Exact official PaddlePaddle Small model SHA256s, verified on Android CI.
# Fail closed if upstream archives change; never silently ship a different model.
EXPECTED_SHA256 = {
    ("det", "inference.onnx"): "d73e0058b7a8086bbd57f3d10b8bcd4ff95363f67e06e2762b5e814fe9c9410e",
    ("rec", "inference.onnx"): "5435fd747c9e0efe15a96d0b378d5bd157e9492ed8fd80edf08f30d02fa24634",
    ("rec", "inference.yml"): "ab078671bb49f06228eadccd34f1bb501e157f7a047095ffb943ba81512c77d1",
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
            # Always overwrite assets; never reuse old Tiny assets during the switch.
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
                    raise RuntimeError(f"PP-OCRv6 Small model checksum mismatch: {path}: {digest}")
                print(f"official PP-OCRv6 Small: {path} ({len(content)} bytes), sha256={digest}")

if __name__ == "__main__":
    main()
