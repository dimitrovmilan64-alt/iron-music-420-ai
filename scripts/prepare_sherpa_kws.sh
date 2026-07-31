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
fi

python3 - "${MODEL_DEST}/tokens.txt" "${MODEL_DEST}/keywords.txt" <<'PY'
from pathlib import Path
import sys

tokens_path = Path(sys.argv[1])
keywords_path = Path(sys.argv[2])

tokens = set()
for raw in tokens_path.read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if not line:
        continue
    tokens.add(line.split()[0])

# Standard CMU pronunciation plus two common compressed variants.
variants = [
    ("HEY_IRON", ["HH", "EY1", "AY1", "ER0", "N"]),
    ("HEY_IRON_ALT", ["HH", "EY1", "AY1", "R", "AH0", "N"]),
    ("HEY_IRON_FAST", ["HH", "EY1", "AY1", "R", "N"]),
]

lines = []
for name, phones in variants:
    missing = [phone for phone in phones if phone not in tokens]
    if not missing:
        lines.append(f"{' '.join(phones)} :3.5 #0.10 @{name}")

if not lines:
    raise SystemExit("No valid Hey Iron pronunciation can be built from tokens.txt")

keywords_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
print("Hey Iron pronunciations:")
print(keywords_path.read_text(encoding="utf-8"))
PY

echo "sherpa-onnx Hey Iron assets are ready."
