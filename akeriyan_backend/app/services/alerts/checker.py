"""Background evaluation of alert rules + the daily auto-briefing.

Runs on a loop from main.py startup. Fetches live price/RSI (reusing the
trading & stocks skills), fires rules with a 1-hour cooldown, and once a day
enqueues the morning briefing at the configured time.
"""
from datetime import datetime, timedelta

from app.services.alerts import store
from app.services.skills import trading, stocks, briefing


async def get_metric(symbol: str) -> dict | None:
    """Return {'price': float, 'rsi': float|None} for a symbol, or None."""
    try:
        r = await trading.analyze(symbol)
        if r.get("ok") and r.get("price") is not None:
            return {"price": float(r["price"]), "rsi": r.get("rsi")}
    except Exception:
        pass
    try:
        r = await stocks.analyze(symbol)
        if r.get("ok") and r.get("price") is not None:
            return {"price": float(r["price"]), "rsi": r.get("rsi")}
    except Exception:
        pass
    return None


def _fmt(v: float) -> str:
    return f"{v:,.2f}".rstrip("0").rstrip(".")


async def _check_rules(now: datetime) -> None:
    for rule in store.active_rules():
        cd = rule.get("cooldown_until") or ""
        if cd and now.isoformat() < cd:
            continue
        metric = await get_metric(rule["symbol"])
        if not metric:
            continue
        value = metric["price"] if rule["kind"] == "price" else metric.get("rsi")
        if value is None:
            continue
        thr = rule["threshold"]
        crossed = (rule["op"] == "above" and value >= thr) or \
                  (rule["op"] == "below" and value <= thr)
        if not crossed:
            continue
        sym = rule["symbol"].upper()
        if rule["kind"] == "price":
            body = f"{sym} price is {_fmt(value)} — {rule['op']} your {_fmt(thr)} alert."
        else:
            body = f"{sym} RSI is {round(value)} — {rule['op']} {round(thr)}."
        if rule.get("note"):
            body += f" ({rule['note']})"
        store.enqueue(f"📈 {sym} alert", body)
        store.set_cooldown(rule["id"], (now + timedelta(hours=1)).isoformat())


async def _check_briefing(now: datetime) -> None:
    btime = store.get_setting("briefing_time", "")
    if not btime:
        return
    today = now.date().isoformat()
    if now.strftime("%H:%M") >= btime and store.get_setting("briefing_last") != today:
        try:
            text = await briefing.morning_briefing()
        except Exception:
            text = "Good morning."
        store.enqueue("☀️ Morning briefing", text)
        store.set_setting("briefing_last", today)


async def check_all() -> None:
    now = datetime.now()
    await _check_rules(now)
    await _check_briefing(now)
