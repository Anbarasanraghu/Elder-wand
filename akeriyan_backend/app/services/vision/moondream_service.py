"""Camera vision via a local vision model (moondream) on Ollama — free, offline.

Takes a photo's bytes + an optional question and returns a spoken answer:
"what is this?", "read this text", "how much is this bill?", etc.
"""
import base64

import httpx

from app.config import settings

_client = httpx.AsyncClient(timeout=httpx.Timeout(180.0, connect=5.0))

_DEFAULT_PROMPT = (
    "Look at this image and answer helpfully. If there is text, read it out. "
    "If it is an object or scene, say what it is. Be concise."
)


async def analyze(image_bytes: bytes, question: str | None = None) -> str:
    prompt = (question or "").strip() or _DEFAULT_PROMPT
    b64 = base64.b64encode(image_bytes).decode()
    try:
        r = await _client.post(
            f"{settings.ollama_url}/api/generate",
            json={
                "model": settings.vision_model,
                "prompt": prompt,
                "images": [b64],
                "stream": False,
                "keep_alive": "30m",
            },
        )
        r.raise_for_status()
        answer = (r.json().get("response") or "").strip()
        return answer or "I couldn't make out the image."
    except Exception as e:  # noqa: BLE001
        print(f"[AKERIYAN] Vision error: {e}")
        return "I couldn't analyze the image right now."
