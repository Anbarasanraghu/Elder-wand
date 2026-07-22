"""Headlines via Google News RSS — free, no key. Read aloud, short and clean."""
import re
import html
import httpx

_client = httpx.AsyncClient(timeout=10.0, follow_redirects=True)


def _titles(xml: str, limit: int) -> list[str]:
    # Grab <title> entries; first one is the feed name, so skip it.
    raw = re.findall(r"<title>(.*?)</title>", xml, flags=re.S)[1:]
    out = []
    for t in raw:
        t = re.sub(r"<!\[CDATA\[(.*?)\]\]>", r"\1", t, flags=re.S)
        t = html.unescape(t).strip()
        # Google News appends " - Publisher"; drop it for cleaner speech.
        t = re.sub(r"\s+-\s+[^-]+$", "", t)
        if t:
            out.append(t)
        if len(out) >= limit:
            break
    return out


async def get_news(topic: str | None, limit: int = 4) -> str:
    try:
        if topic:
            r = await _client.get(
                "https://news.google.com/rss/search",
                params={"q": topic, "hl": "en-IN", "gl": "IN", "ceid": "IN:en"},
            )
        else:
            r = await _client.get(
                "https://news.google.com/rss",
                params={"hl": "en-IN", "gl": "IN", "ceid": "IN:en"},
            )
        titles = _titles(r.text, limit)
        if not titles:
            return "I couldn't find any headlines right now."
        lead = f"Top news about {topic}: " if topic else "Here are the top headlines: "
        return lead + " ... ".join(f"{i}. {t}" for i, t in enumerate(titles, 1))
    except Exception:
        return "I couldn't reach the news service right now."
