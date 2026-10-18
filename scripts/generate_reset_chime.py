#!/usr/bin/env python3
"""Recreate Argon's proposed warm-glass reset chime from its supplied recipe."""

from __future__ import annotations

import math
import struct
import wave
from pathlib import Path


SAMPLE_RATE = 48_000
DURATION = 0.58
TARGET_PEAK = 10 ** (-14.0 / 20.0)
OUTPUT = Path(__file__).resolve().parents[1] / "Sources/CodexUsage/Resources/codex_starlight_restored.wav"


def tone(time: float, start: float, frequency: float, amplitude: float, attack: float, decay: float, pan: float) -> tuple[float, float]:
    elapsed = time - start
    if elapsed < 0:
        return 0.0, 0.0
    envelope = 1.0 if elapsed >= attack else 0.5 * (1.0 - math.cos(math.pi * elapsed / attack))
    value = amplitude * envelope * (
        math.sin(2.0 * math.pi * frequency * elapsed) * math.exp(-elapsed / decay)
        + 0.26 * math.sin(2.0 * math.pi * frequency * 2.0 * elapsed + 0.3) * math.exp(-elapsed / (decay * 0.55))
        + 0.07 * math.sin(2.0 * math.pi * frequency * 3.01 * elapsed + 1.1) * math.exp(-elapsed / (decay * 0.30))
    )
    angle = (pan + 1.0) * (math.pi / 4.0)
    return value * math.cos(angle), value * math.sin(angle)


def main() -> None:
    sample_count = int(SAMPLE_RATE * DURATION)
    left: list[float] = []
    right: list[float] = []
    for index in range(sample_count):
        time = index / SAMPLE_RATE
        layers = (
            tone(time, 0.008, 440.0, 0.62, 0.022, 0.145, -0.12),
            tone(time, 0.010, 329.63, 0.22, 0.028, 0.160, 0.0),
            tone(time, 0.115, 659.25, 0.78, 0.026, 0.155, 0.12),
            tone(time, 0.122, 493.88, 0.20, 0.030, 0.150, -0.05),
        )
        left.append(sum(pair[0] for pair in layers))
        right.append(sum(pair[1] for pair in layers))

    fade_length = round(0.045 * SAMPLE_RATE)
    for offset in range(fade_length):
        fade = 0.5 * (1.0 + math.cos(math.pi * offset / (fade_length - 1)))
        left[-fade_length + offset] *= fade
        right[-fade_length + offset] *= fade

    actual_peak = max(max(map(abs, left)), max(map(abs, right)))
    scale = TARGET_PEAK / actual_peak
    frames = bytearray()
    quantized: list[int] = []
    for left_sample, right_sample in zip(left, right):
        for sample in (left_sample * scale, right_sample * scale):
            value = max(-32768, min(32767, round(sample * 32767.0)))
            quantized.append(value)
            frames.extend(struct.pack("<h", value))

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUTPUT), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(frames)

    peak = max(map(abs, quantized)) / 32767.0
    rms = math.sqrt(sum((value / 32767.0) ** 2 for value in quantized) / len(quantized))
    print(f"Generated {OUTPUT}: {SAMPLE_RATE} Hz, 16-bit stereo, {sample_count} frames, {sample_count / SAMPLE_RATE:.3f}s")
    print(f"Peak {20 * math.log10(peak):.2f} dBFS; RMS {20 * math.log10(rms):.2f} dBFS")


if __name__ == "__main__":
    main()
