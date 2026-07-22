"""Quick facts via DuckDuckGo Instant Answer API — free, no key.

If DDG has no instant answer, we let the local LLM answer from its own
knowledge, so the user still gets a useful spoken reply.
"""
import httpx

from app.services.nlu import llm_nlu

_client = httpx.AsyncClient(timeout=10.0)


async def search(query: str) -> str:
    query = (query or "").strip()
    if not query:
        return "What would you like me to look up?"
    try:
        r = await _client.get(
            "https://api.duckduckgo.com/",
            params={"q": query, "format": "json", "no_html": 1,
                    "skip_disambig": 1},
        )
        d = r.json()
        answer = d.get("AbstractText") or d.get("Answer")
        if not answer:
            topics = d.get("RelatedTopics") or []
            for t in topics:
                if isinstance(t, dict) and t.get("Text"):
                    answer = t["Text"]
                    break
        if answer:
            # Keep it speakable — first couple of sentences only.
            parts = answer.replace("\n", " ").split(". ")
            return ". ".join(parts[:2]).strip().rstrip(".") + "."
    except Exception:
        pass

    # Fallback: ask the local LLM to answer the question directly.
    return await llm_nlu.free_chat(query)
