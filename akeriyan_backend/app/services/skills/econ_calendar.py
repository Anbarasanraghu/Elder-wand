"""Economic calendar via ForexFactory's free weekly JSON feed.

Feed: https://nfs.faireconomy.media/ff_calendar_thisweek.json  (no key)
We filter to the currencies that actually move the asset being analysed,
keep medium/high impact, and compute a countdown + risk flag for each event.
"""
from datetime import datetime, timezone
import httpx

_client = httpx.AsyncClient(timeout=12.0, headers={"User-Agent": "Mozilla/5.0"})
_FEED = "https://nfs.faireconomy.media/ff_calendar_thisweek.json"

_cache: dict = {"at": None, "data": None}


def currencies_for(symbol: str, source: str) -> list[str]:
    """Which currencies' news matter for this symbol."""
    s = (symbol or "").upper()
    if source == "crypto":
        return ["USD"]                       # crypto trades against USD macro
    if s.endswith("=X") and len(s) >= 8:     # forex pair like EURUSD=X
        base, quote = s[0:3], s[3:6]
        return list({base, quote})
    if s.endswith(".NS") or s in ("^NSEI", "^BSESN"):
        return ["INR", "USD"]
    if s in ("GC=F", "SI=F", "CL=F", "XAUUSD=X"):
        return ["USD"]
    return ["USD"]                           # US stocks & default


async def _fetch() -> list:
    now = datetime.now(timezone.utc)
    if _cache["data"] is not None and _cache["at"] and \
       (now - _cache["at"]).total_seconds() < 900:   # 15-min cache
        return _cache["data"]
    try:
        r = await _client.get(_FEED)
        data = r.json() if r.status_code == 200 else []
    except Exception:
        data = []
    _cache["data"], _cache["at"] = data, now
    return data


async def upcoming(symbol: str, source: str, hours: int = 72,
                   limit: int = 6) -> dict:
    events = await _fetch()
    ccys = currencies_for(symbol, source)
    now = datetime.now(timezone.utc)
    out = []
    for e in events:
        if e.get("country") not in ccys:
            continue
        if e.get("impact") not in ("High", "Medium"):
            continue
        try:
            when = datetime.fromisoformat(e["date"]).astimezone(timezone.utc)
        except Exception:
            continue
        delta_h = (when - now).total_seconds() / 3600
        if delta_h < -1 or delta_h > hours:
            continue
        out.append({
            "title": e.get("title", ""),
            "currency": e.get("country", ""),
            "impact": e.get("impact", ""),
            "forecast": e.get("forecast", ""),
            "previous": e.get("previous", ""),
            "when": when.isoformat(),
            "in_hours": round(delta_h, 1),
            "imminent": 0 <= delta_h <= 4 and e.get("impact") == "High",
        })
    out.sort(key=lambda x: x["in_hours"])
    out = out[:limit]

    # Overall news risk for trading right now.
    imminent_high = any(x["imminent"] for x in out)
    next_high = next((x for x in out if x["impact"] == "High" and x["in_hours"] >= -0.5), None)
    return {
        "events": out,
        "news_risk": "high" if imminent_high else
                     ("elevated" if next_high and next_high["in_hours"] <= 12 else "low"),
        "next_high": next_high,
    }
