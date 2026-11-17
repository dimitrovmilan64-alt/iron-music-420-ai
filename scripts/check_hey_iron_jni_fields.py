#!/usr/bin/env python3
"""Assert the release APK DEX still has every field sherpa-onnx JNI looks up.

Flutter 3.47 enables R8 on release builds. If com.k2fsa.sherpa.onnx.* is
obfuscated, KeywordSpotter construction throws:
  RuntimeException: Failed to get field ID for maxActivePaths

This checker parses GetFieldID / SHERPA_ONNX_JNI_READ_* from the pinned
sherpa-onnx JNI sources and compares them to instance fields in the APK DEX.
"""
from __future__ import annotations

import argparse
import re
import struct
import sys
import zipfile
from collections import defaultdict
from pathlib import Path


DEFAULT_JNI_DIR = Path(__file__).resolve().parent / "vendor" / "sherpa-onnx-1.13.4-jni"
KWS_CONFIG = "Lcom/k2fsa/sherpa/onnx/KeywordSpotterConfig;"
ONLINE_MODEL = "Lcom/k2fsa/sherpa/onnx/OnlineModelConfig;"
READ_SIG = {
    "INT": "I",
    "FLOAT": "F",
    "STRING": "Ljava/lang/String;",
    "BOOL": "Z",
}


class _Leb:
    def __init__(self, data: bytes, off: int) -> None:
        self.data = data
        self.off = off

    def uleb(self) -> int:
        result = 0
        shift = 0
        while True:
            byte = self.data[self.off]
            self.off += 1
            result |= (byte & 0x7F) << shift
            if byte & 0x80 == 0:
                return result
            shift += 7


def _u16(data: bytes, off: int) -> int:
    return struct.unpack_from("<H", data, off)[0]


def _u32(data: bytes, off: int) -> int:
    return struct.unpack_from("<I", data, off)[0]


def _mutf8(data: bytes, off: int) -> str:
    reader = _Leb(data, off)
    reader.uleb()
    start = reader.off
    end = start
    while end < len(data) and data[end] != 0:
        end += 1
    return data[start:end].decode("utf-8", "replace")


def dex_instance_fields(dex: bytes) -> dict[str, dict[str, str]]:
    """Return {class_descriptor: {field_name: type_descriptor}} for instance fields."""
    if dex[:4] != b"dex\n":
        raise ValueError("not a DEX file")
    string_ids_size = _u32(dex, 56)
    string_ids_off = _u32(dex, 60)
    type_ids_size = _u32(dex, 64)
    type_ids_off = _u32(dex, 68)
    field_ids_size = _u32(dex, 80)
    field_ids_off = _u32(dex, 84)
    class_defs_size = _u32(dex, 96)
    class_defs_off = _u32(dex, 100)

    strings = [_mutf8(dex, _u32(dex, string_ids_off + i * 4)) for i in range(string_ids_size)]
    types = [strings[_u32(dex, type_ids_off + i * 4)] for i in range(type_ids_size)]
    field_ids: list[tuple[str, str, str]] = []
    for i in range(field_ids_size):
        off = field_ids_off + i * 8
        class_idx = _u16(dex, off)
        type_idx = _u16(dex, off + 2)
        name_idx = _u32(dex, off + 4)
        field_ids.append((types[class_idx], types[type_idx], strings[name_idx]))

    declared: dict[str, dict[str, str]] = {}
    for i in range(class_defs_size):
        off = class_defs_off + i * 32
        class_name = types[_u32(dex, off)]
        class_data_off = _u32(dex, off + 24)
        fields: dict[str, str] = {}
        if class_data_off:
            reader = _Leb(dex, class_data_off)
            static_count = reader.uleb()
            instance_count = reader.uleb()
            direct_count = reader.uleb()
            virtual_count = reader.uleb()
            index = 0
            for _ in range(static_count):
                index += reader.uleb()
                reader.uleb()
            index = 0
            for _ in range(instance_count):
                index += reader.uleb()
                reader.uleb()
                _cls, typ, name = field_ids[index]
                fields[name] = typ
            for _ in range(direct_count + virtual_count):
                reader.uleb()
                reader.uleb()
                reader.uleb()
        declared[class_name] = fields
    return declared


def apk_instance_fields(apk: Path) -> dict[str, dict[str, str]]:
    merged: dict[str, dict[str, str]] = {}
    with zipfile.ZipFile(apk) as archive:
        dex_names = [name for name in archive.namelist() if re.fullmatch(r"classes\d*\.dex", name)]
        if not dex_names:
            raise SystemExit(f"{apk} has no classes*.dex")
        for name in sorted(dex_names):
            for class_name, fields in dex_instance_fields(archive.read(name)).items():
                merged.setdefault(class_name, {}).update(fields)
    return merged


_GET_FIELD = re.compile(
    r'GetFieldID\s*\(\s*(?P<cls>\w+)\s*,\s*"(?P<name>\w+)"\s*,\s*"(?P<sig>[^"]+)"',
)
_READ_MACRO = re.compile(
    r"SHERPA_ONNX_JNI_READ_(?P<kind>INT|FLOAT|STRING|BOOL)\s*\(\s*[^,]+,\s*(?P<name>\w+)\s*,\s*(?P<cls>\w+)\s*,",
)
_OBJ_FIELD = re.compile(
    r"jobject\s+(?P<obj>\w+)\s*=\s*env->GetObjectField\s*\(",
)
_OBJ_CLASS = re.compile(
    r"jclass\s+(?P<cls>\w+)\s*=\s*env->GetObjectClass\s*\(\s*(?P<obj>\w+)\s*\)",
)


def _iter_statements(source: str) -> list[str]:
    packed = re.sub(r"\s+", " ", source)
    parts: list[str] = []
    buf: list[str] = []
    in_string = False
    for char in packed:
        if char == '"' and not (buf and buf[-1] == "\\"):
            in_string = not in_string
            buf.append(char)
        elif char == ";" and not in_string:
            statement = "".join(buf).strip()
            if statement:
                parts.append(statement)
            buf = []
        else:
            buf.append(char)
    tail = "".join(buf).strip()
    if tail:
        parts.append(tail)
    return parts


def parse_expected_fields(jni_dir: Path) -> dict[str, dict[str, str]]:
    kws = (jni_dir / "keyword-spotter.cc").read_text(encoding="utf-8", errors="replace")
    online = (jni_dir / "online-recognizer.cc").read_text(encoding="utf-8", errors="replace")
    kws_fn = _extract_function(kws, "GetKwsConfig")
    model_fn = _extract_function(online, "GetOnlineModelConfig")
    if not kws_fn or not model_fn:
        raise SystemExit(f"Could not find GetKwsConfig / GetOnlineModelConfig in {jni_dir}")

    expected: dict[str, dict[str, str]] = defaultdict(dict)
    # GetKwsConfig(jobject config) / jclass cls
    _collect_fields(kws_fn, {"cls": KWS_CONFIG, "config": KWS_CONFIG}, expected)
    _collect_fields(
        model_fn,
        {"model_config_cls": ONLINE_MODEL, "model_config": ONLINE_MODEL},
        expected,
    )
    return dict(expected)


def _extract_function(source: str, name: str) -> str:
    match = re.search(rf"\b{re.escape(name)}\s*\([^;]*?\)\s*\{{", source)
    if not match:
        return ""
    start = match.end() - 1
    depth = 0
    for index, char in enumerate(source[start:], start):
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start : index + 1]
    return ""


def _collect_fields(
    body: str,
    seed: dict[str, str],
    expected: dict[str, dict[str, str]],
) -> None:
    class_of = dict(seed)
    last_field_sig: str | None = None
    for statement in _iter_statements(body):
        get_match = _GET_FIELD.search(statement)
        if get_match:
            cls_var = get_match.group("cls")
            name = get_match.group("name")
            sig = get_match.group("sig")
            owner = class_of.get(cls_var)
            if not owner:
                raise SystemExit(f"Unknown class variable {cls_var} for field {name}")
            expected[owner][name] = sig
            last_field_sig = sig
        read_match = _READ_MACRO.search(statement)
        if read_match:
            cls_var = read_match.group("cls")
            name = read_match.group("name")
            sig = READ_SIG[read_match.group("kind")]
            owner = class_of.get(cls_var)
            if not owner:
                raise SystemExit(f"Unknown class variable {cls_var} for field {name}")
            expected[owner][name] = sig
        obj_match = _OBJ_FIELD.search(statement)
        if obj_match and last_field_sig:
            class_of[obj_match.group("obj")] = last_field_sig
        cls_match = _OBJ_CLASS.search(statement)
        if cls_match:
            obj = cls_match.group("obj")
            if obj in class_of:
                class_of[cls_match.group("cls")] = class_of[obj]


def format_expected(expected: dict[str, dict[str, str]]) -> str:
    lines = []
    for class_name in sorted(expected):
        for field_name, sig in sorted(expected[class_name].items()):
            lines.append(f"  {class_name}.{field_name} {sig}")
    return "\n".join(lines)


def check_apk(apk: Path, jni_dir: Path) -> int:
    expected = parse_expected_fields(jni_dir)
    actual = apk_instance_fields(apk)
    missing: list[str] = []
    wrong: list[str] = []
    for class_name, fields in sorted(expected.items()):
        declared = actual.get(class_name, {})
        if class_name not in actual:
            missing.append(f"{class_name} (class absent from DEX)")
            continue
        for field_name, sig in sorted(fields.items()):
            if field_name not in declared:
                missing.append(f"{class_name}.{field_name} {sig}")
            elif declared[field_name] != sig:
                wrong.append(
                    f"{class_name}.{field_name}: expected {sig}, found {declared[field_name]}"
                )
    if missing or wrong:
        print("JNI field check FAILED. R8 likely renamed or stripped sherpa-onnx classes.")
        if missing:
            print("Missing:")
            for item in missing:
                print(f"  - {item}")
        if wrong:
            print("Wrong signature:")
            for item in wrong:
                print(f"  - {item}")
        kws = actual.get(KWS_CONFIG, {})
        print("KeywordSpotterConfig instance fields in the APK:")
        if kws:
            for name, sig in sorted(kws.items()):
                print(f"  {name}: {sig}")
        else:
            print("  (none / class missing)")
        return 1
    print(f"OK JNI fields in {apk.name}:")
    print(format_expected(expected))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path)
    parser.add_argument("--jni-dir", type=Path, default=DEFAULT_JNI_DIR)
    parser.add_argument(
        "--print-expected",
        action="store_true",
        help="Print parsed JNI fields and exit without checking an APK",
    )
    args = parser.parse_args()
    if not args.jni_dir.is_dir():
        raise SystemExit(f"JNI source dir not found: {args.jni_dir}")
    if args.print_expected or args.apk is None:
        if args.print_expected:
            print(format_expected(parse_expected_fields(args.jni_dir)))
            return 0
        raise SystemExit("--apk is required unless --print-expected is set")
    if not args.apk.is_file():
        raise SystemExit(f"APK not found: {args.apk}")
    return check_apk(args.apk, args.jni_dir)


if __name__ == "__main__":
    sys.exit(main())
