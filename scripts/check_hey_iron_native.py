#!/usr/bin/env python3
"""Verify the bundled Hey Iron model files and 16 KB ELF alignment of sherpa .so files."""
from __future__ import annotations

import argparse
import struct
import sys
import zipfile
from pathlib import Path

REQUIRED_FILES = (
    "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
    "decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
    "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
    "tokens.txt",
    "keywords.txt",
)
REQUIRED_SO = (
    "lib/arm64-v8a/libonnxruntime.so",
    "lib/arm64-v8a/libsherpa-onnx-jni.so",
    "lib/arm64-v8a/libsherpa-onnx-c-api.so",
)
MIN_ALIGN = 0x4000


def max_pt_load_align(data: bytes) -> int:
    if data[:4] != b"\x7fELF":
        raise ValueError("not an ELF file")
    endian = "<" if data[5] == 1 else ">"
    if data[4] != 2:
        raise ValueError("expected ELF64")
    e_phoff = struct.unpack_from(endian + "Q", data, 32)[0]
    e_phentsize = struct.unpack_from(endian + "H", data, 54)[0]
    e_phnum = struct.unpack_from(endian + "H", data, 56)[0]
    aligns = []
    for i in range(e_phnum):
        off = e_phoff + i * e_phentsize
        p_type = struct.unpack_from(endian + "I", data, off)[0]
        if p_type != 1:
            continue
        p_align = struct.unpack_from(endian + "Q", data, off + 48)[0]
        aligns.append(p_align)
    if not aligns:
        raise ValueError("no PT_LOAD segments")
    return min(aligns)


def check_assets(asset_dir: Path) -> None:
    missing = []
    for name in REQUIRED_FILES:
        path = asset_dir / name
        if not path.is_file() or path.stat().st_size <= 0:
            missing.append(name)
    if missing:
        raise SystemExit(f"Missing or empty Hey Iron model files in {asset_dir}: {', '.join(missing)}")
    keywords = (asset_dir / "keywords.txt").read_text(encoding="utf-8")
    if "HEY_IRON" not in keywords or "HEY_IRON_BG" not in keywords:
        raise SystemExit("keywords.txt must contain Hey Iron and Bulgarian HEY_IRON_BG variants")


def check_zip_libs(archive: Path, label: str) -> None:
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        for so_name in REQUIRED_SO:
            # AARs and APKs both use lib/arm64-v8a/...
            if so_name not in names:
                # some AARs use jni/arm64-v8a
                alt = so_name.replace("lib/arm64-v8a/", "jni/arm64-v8a/")
                if alt in names:
                    so_name = alt
                else:
                    raise SystemExit(f"{label} is missing {so_name}")
            data = z.read(so_name)
            align = max_pt_load_align(data)
            if align < MIN_ALIGN:
                raise SystemExit(
                    f"{label}:{so_name} PT_LOAD alignment is {align} (0x{align:x}), need >= 16KB"
                )
            print(f"OK {label}:{so_name} min PT_LOAD align=0x{align:x}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--aar", type=Path)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--assets", type=Path)
    args = parser.parse_args()
    if args.assets:
        check_assets(args.assets)
        print(f"OK bundled model files in {args.assets}")
    if args.aar:
        if not args.aar.is_file():
            raise SystemExit(f"Missing sherpa AAR: {args.aar}")
        check_zip_libs(args.aar, "aar")
    if args.apk:
        if not args.apk.is_file():
            raise SystemExit(f"Missing APK: {args.apk}")
        check_zip_libs(args.apk, "apk")
    if not args.assets and not args.aar and not args.apk:
        raise SystemExit("Pass --assets, --aar and/or --apk")
    return 0


if __name__ == "__main__":
    sys.exit(main())
