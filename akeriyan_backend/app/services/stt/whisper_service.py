# NOTE: STT is now done ON-DEVICE (the phone's speech_to_text), so this backend
# Whisper path is optional. `faster_whisper` is imported LAZILY so the backend
# runs (and free-hosts) fine WITHOUT the heavy STT dependency installed; the
# /stt endpoint only needs it if you actually call it locally.
_MODEL_SIZE = "small"

_model = None


def get_model():
    """Load the model once and reuse it (first call downloads it).
    Raises ImportError if faster-whisper isn't installed (STT is on-device now)."""
    global _model
    if _model is None:
        from faster_whisper import WhisperModel  # lazy — optional on the server
        print(f"[AKERIYAN] Loading Whisper model '{_MODEL_SIZE}'...")
        _model = WhisperModel(_MODEL_SIZE, device="cpu", compute_type="int8")
        print("[AKERIYAN] Whisper model ready.")
    return _model


def transcribe_file(path: str) -> dict:
    model = get_model()
    # Speed tuning for short voice commands on CPU:
    #  - beam_size=1  : greedy decode, ~2x faster than the default beam of 5,
    #                   with negligible accuracy loss on short clips.
    #  - condition_on_previous_text=False : no cross-segment context to carry,
    #                   so decoding starts clean and fast every time.
    # language=None -> auto-detect (enables Tamil + English bilingual use).
    segments, info = model.transcribe(
        path,
        language=None,
        vad_filter=True,
        beam_size=1,
        condition_on_previous_text=False,
    )
    text = " ".join(seg.text.strip() for seg in segments).strip()
    return {
        "text": text,
        "language": info.language,
        "language_probability": round(getattr(info, "language_probability", 0), 3),
        "duration_ms": int(info.duration * 1000),
    }