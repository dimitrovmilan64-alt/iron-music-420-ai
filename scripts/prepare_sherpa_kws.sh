#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AAR_VERSION="1.13.4"
MODEL_NAME="sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
AAR_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${AAR_VERSION}/sherpa-onnx-${AAR_VERSION}.aar"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/${MODEL_NAME}.tar.bz2"

LIB_DIR="${ROOT_DIR}/android/app/libs"
ASSET_DIR="${ROOT_DIR}/android/app/src/main/assets/hey_iron"
FLUTTER_KEYWORDS="${ROOT_DIR}/assets/hey_iron/keywords.txt"
AAR_DEST="${LIB_DIR}/sherpa-onnx-${AAR_VERSION}.aar"

mkdir -p "${LIB_DIR}" "${ASSET_DIR}" "$(dirname "${FLUTTER_KEYWORDS}")"

if [[ ! -s "${AAR_DEST}" ]]; then
  echo "Downloading sherpa-onnx Android runtime ${AAR_VERSION}..."
  curl --location --fail --retry 3 --retry-delay 2 \
    --output "${AAR_DEST}.download" "${AAR_URL}"
  mv "${AAR_DEST}.download" "${AAR_DEST}"
fi

required_model_files=(
  "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
  "decoder-epoch-13-avg-2-chunk-16-left-64.onnx"
  "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx"
  "tokens.txt"
  "keywords.txt"
)

model_ready=true
for file in "${required_model_files[@]}"; do
  if [[ ! -s "${ASSET_DIR}/${file}" ]]; then
    model_ready=false
    break
  fi
done

if [[ "${model_ready}" != true ]]; then
  echo "Preparing the small Hey Iron keyword model for the APK (~5.5 MB, not the 33 MB archive)..."
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' EXIT
  archive="${temp_dir}/${MODEL_NAME}.tar.bz2"
  # Reuse a previously downloaded archive when present.
  if [[ -s /tmp/hey-iron-model.tar.bz2 ]]; then
    cp /tmp/hey-iron-model.tar.bz2 "${archive}"
  else
    curl --location --fail --retry 3 --retry-delay 2 \
      --output "${archive}" "${MODEL_URL}"
  fi
  python3 - "${archive}" "${temp_dir}" <<'PYTAR'
import tarfile, sys
from pathlib import Path
archive, dest = Path(sys.argv[1]), Path(sys.argv[2])
with tarfile.open(archive, "r:bz2") as tf:
    tf.extractall(dest)
PYTAR
  source_dir="${temp_dir}/${MODEL_NAME}"
  mkdir -p "${ASSET_DIR}"
  cp "${source_dir}/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx" "${ASSET_DIR}/"
  cp "${source_dir}/decoder-epoch-13-avg-2-chunk-16-left-64.onnx" "${ASSET_DIR}/"
  cp "${source_dir}/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx" "${ASSET_DIR}/"
  cp "${source_dir}/tokens.txt" "${ASSET_DIR}/"
  cp "${source_dir}/en.phone" "${ASSET_DIR}/"
fi

python3 - \
  "${ASSET_DIR}/tokens.txt" \
  "${ASSET_DIR}/en.phone" \
  "${ASSET_DIR}/keywords.txt" \
  "${FLUTTER_KEYWORDS}" <<'PY'
from pathlib import Path
import re
import sys

tokens_path = Path(sys.argv[1])
lexicon_path = Path(sys.argv[2])
keywords_path = Path(sys.argv[3])
flutter_keywords = Path(sys.argv[4])

tokens = set()
for raw in tokens_path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if line:
        tokens.add(line.split()[0])

lexicon: dict[str, list[list[str]]] = {}
for raw in lexicon_path.read_text(encoding="utf-8").splitlines():
    parts = raw.strip().split()
    if len(parts) < 2:
        continue
    word = re.sub(r"\(\d+\)$", "", parts[0].upper())
    lexicon.setdefault(word, []).append(parts[1:])

candidates: list[tuple[str, list[str], float, float]] = []

# English "Hey Iron" from the official CMU lexicon shipped with the model.
for hey_index, hey in enumerate(lexicon.get("HEY", []), start=1):
    for iron_index, iron in enumerate(lexicon.get("IRON", []), start=1):
        candidates.append(
            (f"HEY_IRON_{hey_index}_{iron_index}", hey + iron, 3.0, 0.05)
        )

# Bulgarian-accented «Хей Айрън» / «Хей Айрън» approximated with CMU phones.
candidates.extend(
    [
        ("HEY_IRON_BG", ["HH", "EY1", "AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("HEY_IRON_BG_STRESS", ["HH", "EY1", "AY1", "R", "AH1", "N"], 3.0, 0.05),
        ("HEY_IRON_BG_FAST", ["HH", "EY1", "AY1", "R", "N"], 3.0, 0.05),
        ("HEY_IRON_BG_EH", ["HH", "EH1", "Y", "AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("HEY_IRON_BG_EH_SHORT", ["HH", "EH1", "AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("HEY_IRON_BG_O", ["HH", "EY1", "AY1", "R", "AO0", "N"], 3.0, 0.05),
        ("HEY_IRON_BG_OW", ["HH", "EY1", "AY1", "R", "OW0", "N"], 3.0, 0.05),
        ("HEY_IRON_ER", ["HH", "EY1", "AY1", "ER0", "N"], 3.0, 0.05),
        ("HI_IRON", ["HH", "AY1", "AY1", "ER0", "N"], 3.0, 0.05),
        ("HI_IRON_BG", ["HH", "AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("HI_IRON_BG2", ["HH", "AY1", "AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("AY_IRON", ["EY1", "AY1", "ER0", "N"], 3.0, 0.05),
        ("AY_IRON_SHORT", ["AY1", "AY1", "ER0", "N"], 3.0, 0.05),
        ("AY_IRON_BG", ["AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("AY_IRON_OPEN", ["EY1", "AY1", "R", "AH0", "N"], 3.0, 0.05),
        ("HEY_IRON_REDUCED", ["HH", "EY1", "R", "AH0", "N"], 3.0, 0.05),
    ]
)

lines: list[str] = []
seen: set[tuple[str, ...]] = set()
for name, phones, score, threshold in candidates:
    key = tuple(phones)
    if key in seen:
        continue
    if any(phone not in tokens for phone in phones):
        continue
    seen.add(key)
    lines.append(f"{' '.join(phones)} :{score:.1f} #{threshold:.2f} @{name}")

if not lines:
    raise SystemExit("No valid Hey Iron pronunciation can be built from tokens.txt")

text = "\n".join(lines) + "\n"
keywords_path.write_text(text, encoding="utf-8")
flutter_keywords.parent.mkdir(parents=True, exist_ok=True)
flutter_keywords.write_text(text, encoding="utf-8")
print(f"Hey Iron pronunciations enabled: {len(lines)}")
print(text)
PY

# en.phone is only used to build keywords.txt; do not ship it in the APK.
rm -f "${ASSET_DIR}/en.phone"

python3 "${ROOT_DIR}/scripts/check_hey_iron_native.py" --aar "${AAR_DEST}" --assets "${ASSET_DIR}"

echo "sherpa-onnx Hey Iron assets are ready (small bundled model)."
