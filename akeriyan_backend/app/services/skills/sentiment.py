"""Market sentiment: crypto Fear & Greed + recent headlines.

Fetch-only (no LLM here) so it's fast — the single decision LLM call reads the
headlines and infers the news mood, keeping the pro endpoint responsive.
"""
import asyncio
import httpx

from app.services.skills import news

_client = httpx.AsyncClient(timeout=10.0, headers={"User-Agent": "Mozilla/5.0"})


async def crypto_fear_greed() -> dict | None:
    try:
        r = await _client.get("https://api.alternative.me/fng/?limit=1")
        d = r.json()["data"][0]
        return {"value": int(d["value"]), "label": d["value_classification"]}
    except Exception:
        return None


async def get(name: str, is_crypto: bool) -> dict:
    fng_task = crypto_fear_greed() if is_crypto else _none()
    headlines_task = news.get_news(name, limit=5)
    fng, headlines = await asyncio.gather(fng_task, headlines_task)
    # mood is filled later by the decision LLM (single call).
    return {"fear_greed": fng, "news": {"mood": "neutral", "summary": headlines}}


async def _none():
    return None
