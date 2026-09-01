#!/usr/bin/env python3
"""Transcribe a 16 kHz mono WAV and print the text to stdout."""

from __future__ import annotations

import array
import sys
import wave

import transcribe_cpp


def load_wav_mono16k(path: str) -> array.array:
    with wave.open(path, "rb") as w:
        n_channels = w.getnchannels()
        sample_width = w.getsampwidth()
        framerate = w.getframerate()
        frames = w.readframes(w.getnframes())

    if sample_width != 2:
        raise SystemExit(f"{path}: expected 16-bit PCM, got {sample_width * 8}-bit")
    if framerate != 16000:
        raise SystemExit(
            f"{path}: expected 16 kHz, got {framerate} Hz — resample first, e.g. "
            f"ffmpeg -i in.wav -ar 16000 -ac 1 out.wav"
        )

    pcm16 = array.array("h")
    pcm16.frombytes(frames)
    if sys.byteorder == "big":
        pcm16.byteswap()

    if n_channels > 1:
        mono = array.array("h", [0]) * (len(pcm16) // n_channels)
        for i in range(len(mono)):
            acc = sum(pcm16[i * n_channels + c] for c in range(n_channels))
            mono[i] = int(acc / n_channels)
        pcm16 = mono

    return array.array("f", (s / 32768.0 for s in pcm16))


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: transcribe.py <model.gguf> <audio.wav>", file=sys.stderr)
        return 1

    model_path, audio_path = sys.argv[1], sys.argv[2]
    pcm = load_wav_mono16k(audio_path)

    with transcribe_cpp.Model(model_path, backend="auto") as model:
        with model.session() as session:
            result = session.run(pcm)

    text = result.text.strip()
    if text:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
