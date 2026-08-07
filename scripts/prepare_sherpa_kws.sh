#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AAR_VERSION="1.13.4"
MODEL_NAME="sherpa-onnx-kws-zipformer-zh-en-3M-2025-12-20"
AAR_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/v${AAR_VERSION}/sherpa-onnx-${AAR_VERSION}.aar"
MODEL_URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/kws-models/${MODEL_NAME}.tar.bz2"

LIB_DIR="${ROOT_DIR}/android/app/libs"
ASSETS_ROOT="${ROOT_DIR}/android/app/src/main/assets"
MODEL_DEST="${ASSETS_ROOT}/${MODEL_NAME}"
AAR_DEST="${LIB_DIR}/sherpa-onnx-${AAR_VERSION}.aar"

mkdir -p "${LIB_DIR}" "${ASSETS_ROOT}"

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
  "en.phone"
  "keywords.txt"
)

model_ready=true
for file in "${required_model_files[@]}"; do
  if [[ ! -s "${MODEL_DEST}/${file}" ]]; then
    model_ready=false
    break
  fi
done

if [[ "${model_ready}" != true ]]; then
  echo "Downloading the open-source Hey Iron keyword model..."
  temp_dir="$(mktemp -d)"
  trap 'rm -rf "${temp_dir}"' EXIT
  archive="${temp_dir}/${MODEL_NAME}.tar.bz2"

  curl --location --fail --retry 3 --retry-delay 2 \
    --output "${archive}" "${MODEL_URL}"
  tar -xjf "${archive}" -C "${temp_dir}"

  source_dir="${temp_dir}/${MODEL_NAME}"
  rm -rf "${MODEL_DEST}"
  mkdir -p "${MODEL_DEST}"

  cp "${source_dir}/encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx" "${MODEL_DEST}/"
  cp "${source_dir}/decoder-epoch-13-avg-2-chunk-16-left-64.onnx" "${MODEL_DEST}/"
  cp "${source_dir}/joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx" "${MODEL_DEST}/"
  cp "${source_dir}/tokens.txt" "${MODEL_DEST}/"
  cp "${source_dir}/en.phone" "${MODEL_DEST}/"
fi

python3 - \
  "${MODEL_DEST}/tokens.txt" \
  "${MODEL_DEST}/en.phone" \
  "${MODEL_DEST}/keywords.txt" <<'PY'
from pathlib import Path
import re
import sys

tokens_path = Path(sys.argv[1])
lexicon_path = Path(sys.argv[2])
keywords_path = Path(sys.argv[3])

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

# Use the model's own dictionary. Values stay close to sherpa-onnx's documented
# defaults (score 1.0, threshold 0.25) so ordinary speech cannot wake Iron.
for hey_index, hey in enumerate(lexicon.get("HEY", []), start=1):
    for iron_index, iron in enumerate(lexicon.get("IRON", []), start=1):
        candidates.append(
            (f"HEY_IRON_LEX_{hey_index}_{iron_index}", hey + iron, 1.8, 0.28)
        )
        if hey and hey[0] == "HH":
            candidates.append(
                (
                    f"HEY_IRON_LEX_NO_H_{hey_index}_{iron_index}",
                    hey[1:] + iron,
                    1.4,
                    0.38,
                )
            )

# Common recognition variant: „Hey Aaron“ / „Хей Аарън“.
for hey_index, hey in enumerate(lexicon.get("HEY", []), start=1):
    for aaron_index, aaron in enumerate(lexicon.get("AARON", []), start=1):
        candidates.append(
            (f"HEY_AARON_LEX_{hey_index}_{aaron_index}", hey + aaron, 1.5, 0.35)
        )

# Bulgarian-accented, relaxed and compressed variants of „Хей Айрън“.
candidates.extend(
    [
        ("HEY_IRON_BG", ["HH", "EY1", "AY1", "R", "AH0", "N"], 1.8, 0.28),
        ("HEY_IRON_BG_FAST", ["HH", "EY1", "AY1", "R", "N"], 1.7, 0.30),
        ("HEY_IRON_BG_EH", ["HH", "EH1", "Y", "AY1", "R", "AH0", "N"], 1.6, 0.32),
        ("HEY_IRON_BG_EH_SHORT", ["HH", "EH1", "AY1", "R", "AH0", "N"], 1.6, 0.32),
        ("HEY_IRON_NO_H", ["EY1", "AY1", "R", "AH0", "N"], 1.4, 0.38),
        ("HEY_IRON_NO_H_FAST", ["EY1", "AY1", "R", "N"], 1.3, 0.40),
        ("HEY_IRON_BG_O", ["HH", "EY1", "AY1", "R", "AO0", "N"], 1.5, 0.35),
        ("HEY_IRON_BG_OW", ["HH", "EY1", "AY1", "R", "OW0", "N"], 1.5, 0.35),
        ("HEY_IRON_NO_H_O", ["EY1", "AY1", "R", "AO0", "N"], 1.3, 0.42),
        ("HEY_IRON_NO_H_OW", ["EY1", "AY1", "R", "OW0", "N"], 1.3, 0.42),
        ("HEY_AARON_BG", ["HH", "EY1", "EH1", "R", "AH0", "N"], 1.5, 0.35),
        ("HEY_AARON_BG_FAST", ["HH", "EY1", "EH1", "R", "N"], 1.4, 0.38),
        ("HEY_AARON_NO_H", ["EY1", "EH1", "R", "AH0", "N"], 1.3, 0.42),
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
    lines.append(
        f"{' '.join(phones)} :{score:.1f} #{threshold:.2f} @{name}"
    )

if not lines:
    raise SystemExit("No valid Hey Iron pronunciation can be built from tokens.txt")

keywords_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"Hey Iron pronunciations enabled: {len(lines)}")
print(keywords_path.read_text(encoding="utf-8"))
PY

echo "sherpa-onnx Hey Iron assets are ready."
