
"""Free local LLM brain via Ollama (https://ollama.com).

Everything here runs on your own PC — no API keys, no cost, fully offline.
If Ollama is not installed/running, every function degrades gracefully so
AKERIYAN keeps working on the fast rule engine alone.
"""
import json
import httpx

from app.config import settings

# One shared async client (keeps connections warm = faster replies).
_client = httpx.AsyncClient(timeout=httpx.Timeout(120.0, connect=3.0))

_available_cache: bool | None = None


async def is_available() -> bool:
    """True if an Ollama server is reachable. Cached after first success."""
    global _available_cache
    if not settings.llm_enabled:
        return False
    if _available_cache:
        return True
    try:
        r = await _client.get(f"{settings.ollama_url}/api/tags", timeout=3.0)
        _available_cache = r.status_code == 200
    except Exception:
        _available_cache = False
    return bool(_available_cache)


async def chat(messages: list[dict], *, json_mode: bool = False,
               temperature: float = 0.4, max_tokens: int | None = None) -> str:
    """Send a chat conversation to the local model and return its text reply.

    `messages` = [{"role": "system"|"user"|"assistant", "content": "..."}]
    `max_tokens` caps generation (num_predict) — key for CPU response time.
    Raises if the model can't be reached — callers decide the fallback.
    """
    # num_ctx bounds prompt-processing cost. llama3.2 advertises a 128k window;
    # without a cap Ollama can allocate/process far more than we need and slow
    # down prompt eval. 4096 comfortably fits our system prompt + short history.
    options = {"temperature": temperature, "num_ctx": 4096}
    if max_tokens:
        options["num_predict"] = max_tokens
    payload = {
        "model": settings.ollama_model,
        "messages": messages,
        "stream": False,
        "options": options,
        "keep_alive": "30m",   # keep model warm -> faster repeat calls
    }
    if json_mode:
        payload["format"] = "json"

    r = await _client.post(f"{settings.ollama_url}/api/chat", json=payload)
    r.raise_for_status()
    data = r.json()
    return (data.get("message", {}).get("content") or "").strip()


async def chat_stream(messages: list[dict], *, temperature: float = 0.4,
                      max_tokens: int | None = None):
    """Async-generator version of chat(): yields text deltas as the model
    produces them, so callers can start speaking the first sentence early."""
    options = {"temperature": temperature, "num_ctx": 4096}
    if max_tokens:
        options["num_predict"] = max_tokens
    payload = {
        "model": settings.ollama_model,
        "messages": messages,
        "stream": True,
        "options": options,
        "keep_alive": "30m",
    }
    async with _client.stream("POST", f"{settings.ollama_url}/api/chat",
                              json=payload) as r:
        r.raise_for_status()
        async for line in r.aiter_lines():
            if not line.strip():
                continue
            try:
                data = json.loads(line)
            except Exception:
                continue
            tok = data.get("message", {}).get("content")
            if tok:
                yield tok
            if data.get("done"):
                break


async def warmup() -> None:
    """Preload the model into RAM so the first real request isn't a cold start.
    Fire-and-forget from app startup; failures are harmless."""
    try:
        if await is_available():
            await chat([{"role": "user", "content": "hi"}], max_tokens=1)
    except Exception:
        pass


async def chat_json(messages: list[dict], max_tokens: int | None = None) -> dict:
    """Chat that must return a JSON object. Returns {} on any parse failure."""
    raw = await chat(messages, json_mode=True, temperature=0.1,
                     max_tokens=max_tokens)
    try:
        return json.loads(raw)
    except Exception:
        # Some models wrap JSON in prose — grab the first {...} block.
        start, end = raw.find("{"), raw.rfind("}")
        if 0 <= start < end:
            try:
                return json.loads(raw[start:end + 1])
            except Exception:
                return {}
        return {}
