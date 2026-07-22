"""Natural offline voice via Piper (https://github.com/rhasspy/piper).

Runs the bundled piper.exe with a neural voice model to synthesise speech as
WAV bytes — completely free, offline, no API key. If the binary/voice is
missing or synthesis fails, callers fall back to the phone's built-in TTS.
"""
import asyncio
import os
import tempfile
from pathlib import Path

# akeriyan_backend/piper/{piper/piper.exe, voices/*.onnx}
_BASE = Path(__file__).resolve().parents[3] / "piper"
_PIPER = _BASE / "piper" / "piper.exe"
_VOICE = _BASE / "voices" / "en_US-amy-medium.onnx"


def available() -> bool:
    return _PIPER.exists() and _VOICE.exists()


def _run(text: str) -> bytes:
    fd, out = tempfile.mkstemp(suffix=".wav")
    os.close(fd)
    try:
        import subprocess
        subprocess.run(
            [str(_PIPER), "-m", str(_VOICE), "-f", out],
            input=text.encode("utf-8"),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
            cwd=str(_BASE),
        )
        return Path(out).read_bytes()
    finally:
        try:
            os.unlink(out)
        except OSError:
            pass


async def synthesize(text: str) -> bytes | None:
    """Return WAV audio bytes for `text`, or None to signal 'use device TTS'."""
    text = (text or "").strip()
    if not text or not available():
        return None
    try:
        return await asyncio.to_thread(_run, text)
    except Exception as e:  # noqa: BLE001
        print(f"[AKERIYAN] Piper TTS error: {e}")
        return None
