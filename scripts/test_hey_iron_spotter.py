#!/usr/bin/env python3
"""Feed a generated "hey iron" wav through the bundled sherpa-onnx KWS model.

Exits 0 on detection. Exits 2 if sherpa-onnx or a TTS/wav source is missing
so unit CI can skip. Exits 1 on a hard failure (model missing, no detection).
"""
from __future__ import annotations

import argparse
import math
import struct
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODEL_DIR = ROOT / "android/app/src/main/assets/hey_iron"
FIXTURE = ROOT / "test/fixtures/hey_iron.wav"


def require_model() -> None:
    needed = [
        "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
        "decoder-epoch-13-avg-2-chunk-16-left-64.onnx",
        "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx",
        "tokens.txt",
        "keywords.txt",
    ]
    missing = [name for name in needed if not (MODEL_DIR / name).is_file()]
    if missing:
        raise SystemExit(f"Bundled Hey Iron model is incomplete: {missing}")


def load_wav(path: Path) -> tuple[int, list[float]]:
    with wave.open(str(path), "rb") as handle:
        if handle.getsampwidth() != 2:
            raise SystemExit(f"{path} is not 16-bit PCM")
        channels = handle.getnchannels()
        rate = handle.getframerate()
        frames = handle.readframes(handle.getnframes())
    samples = list(struct.unpack("<" + "h" * (len(frames) // 2), frames))
    if channels == 2:
        samples = [
            int((samples[i] + samples[i + 1]) / 2)
            for i in range(0, len(samples), 2)
        ]
    return rate, [value / 32768.0 for value in samples]


def write_wav(path: Path, rate: int, samples: list[float]) -> None:
    clipped = [
        max(-32768, min(32767, int(value * 32767.0))) for value in samples
    ]
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(rate)
        handle.writeframes(struct.pack("<" + "h" * len(clipped), *clipped))


def resample(samples: list[float], src_rate: int, dst_rate: int) -> list[float]:
    if src_rate == dst_rate:
        return samples
    if not samples:
        return samples
    duration = len(samples) / float(src_rate)
    count = max(1, int(round(duration * dst_rate)))
    out: list[float] = []
    for index in range(count):
        pos = index * src_rate / float(dst_rate)
        left = min(len(samples) - 1, int(math.floor(pos)))
        right = min(len(samples) - 1, left + 1)
        frac = pos - left
        out.append(samples[left] * (1.0 - frac) + samples[right] * frac)
    return out


def silence(rate: int, seconds: float) -> list[float]:
    return [0.0] * int(rate * seconds)


def generate_wav(out: Path) -> Path:
    if FIXTURE.is_file() and FIXTURE.stat().st_size > 0:
        rate, samples = load_wav(FIXTURE)
        samples = (
            silence(16000, 0.3)
            + resample(samples, rate, 16000)
            + silence(16000, 0.4)
        )
        write_wav(out, 16000, samples)
        return out

    tts_cmds = [
        ["espeak-ng", "-v", "en-us", "-s", "140", "-w", str(out), "hey iron"],
        ["espeak", "-v", "en-us", "-s", "140", "-w", str(out), "hey iron"],
    ]
    for cmd in tts_cmds:
        try:
            completed = subprocess.run(cmd, check=False, capture_output=True)
        except FileNotFoundError:
            continue
        if completed.returncode == 0 and out.is_file() and out.stat().st_size > 0:
            rate, samples = load_wav(out)
            padded = silence(16000, 0.3) + resample(samples, rate, 16000) + silence(16000, 0.4)
            write_wav(out, 16000, padded)
            return out
    raise FileNotFoundError("no wav fixture and no espeak/espeak-ng")


def run_spotter(samples: list[float], sample_rate: int) -> str:
    try:
        import sherpa_onnx
    except ImportError as error:
        raise ImportError("sherpa_onnx is not installed") from error

    spotter = sherpa_onnx.KeywordSpotter(
        tokens=str(MODEL_DIR / "tokens.txt"),
        encoder=str(MODEL_DIR / "encoder-epoch-13-avg-2-chunk-16-left-64.int8.onnx"),
        decoder=str(MODEL_DIR / "decoder-epoch-13-avg-2-chunk-16-left-64.onnx"),
        joiner=str(MODEL_DIR / "joiner-epoch-13-avg-2-chunk-16-left-64.int8.onnx"),
        keywords_file=str(MODEL_DIR / "keywords.txt"),
        num_threads=1,
        sample_rate=sample_rate,
        feature_dim=80,
        max_active_paths=4,
        keywords_score=2.5,
        keywords_threshold=0.10,
        num_trailing_blanks=1,
        provider="cpu",
    )
    stream = spotter.create_stream()
    # Feed in ~100ms chunks the same way the Android engine does.
    frame = 1600
    detected = ""
    for start in range(0, len(samples), frame):
        chunk = samples[start : start + frame]
        stream.accept_waveform(sample_rate, chunk)
        while spotter.is_ready(stream):
            spotter.decode_stream(stream)
            result = spotter.get_result(stream)
            keyword = getattr(result, "keyword", None) or str(result)
            if keyword and keyword not in ("", "''", '""'):
                detected = str(keyword)
                break
        if detected:
            break
    if not detected:
        stream.input_finished()
        while spotter.is_ready(stream):
            spotter.decode_stream(stream)
            result = spotter.get_result(stream)
            keyword = getattr(result, "keyword", None) or str(result)
            if keyword and keyword not in ("", "''", '""'):
                detected = str(keyword)
                break
    return detected


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--wav", type=Path, default=None)
    parser.add_argument("--allow-skip", action="store_true")
    args = parser.parse_args()
    require_model()

    with tempfile.TemporaryDirectory() as tmp:
        wav_path = args.wav
        if wav_path is None:
            generated = Path(tmp) / "hey_iron.wav"
            try:
                wav_path = generate_wav(generated)
            except FileNotFoundError as error:
                message = f"SKIP: cannot synthesize hey iron wav ({error})"
                print(message)
                return 0 if args.allow_skip else 2
        try:
            rate, samples = load_wav(wav_path)
        except Exception as error:  # noqa: BLE001
            print(f"Failed to read {wav_path}: {error}", file=sys.stderr)
            return 1
        samples = resample(samples, rate, 16000)
        try:
            detected = run_spotter(samples, 16000)
        except ImportError as error:
            print(f"SKIP: {error}")
            return 0 if args.allow_skip else 2
        except Exception as error:  # noqa: BLE001
            print(f"Keyword spotter failed: {error}", file=sys.stderr)
            return 1

    if not detected:
        print("FAIL: keyword spotter did not detect 'hey iron'")
        return 1
    print(f"OK: detected {detected}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
