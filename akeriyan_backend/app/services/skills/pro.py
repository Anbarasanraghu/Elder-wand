"""PRO terminal — the full institutional analysis in one call.

Combines: multi-timeframe scalp read (bias, S/R, order blocks, setup) +
liquidity map + economic calendar (ForexFactory) + sentiment + FX session,
then runs the AI decision engine over everything and returns one bundle
the app renders as a trading terminal.
"""
import asyncio

from app.services.skills import scalp, liquidity, econ_calendar, sentiment, \
    sessions, decision


async def analyze(spoken: str | None) -> dict:
    base = await scalp.analyze(spoken)
    if not base.get("ok"):
        return base

    candles = base["candles"]
    is_crypto = base.get("source") == "crypto"

    liq = liquidity.analyze(candles)          # sync, instant
    sess = sessions.active_session()          # sync, instant
    # Fetch calendar + sentiment concurrently.
    cal, sent = await asyncio.gather(
        econ_calendar.upcoming(base["symbol"], base.get("source", "")),
        sentiment.get(base["base"], is_crypto),
    )

    ctx = {
        "base": base["base"],
        "price": base["price"],
        "bias": base["bias"],
        "timeframes": base["timeframes"],
        "supports": base["supports"],
        "resistances": base["resistances"],
        "setup": base["setup"],
        "liquidity": liq,
        "calendar": cal,
        "sentiment": sent,
        "session": sess,
    }
    verdict = await decision.decide(ctx)
    # Apply the LLM-inferred news mood back onto the sentiment block.
    if verdict.get("news_mood"):
        sent["news"]["mood"] = verdict["news_mood"]

    # Concise spoken briefing (voice reply).
    parts = [f"{base['base']} decision: {verdict['action']}, "
             f"{verdict['confidence']} confidence, "
             f"confluence score {verdict['score']} out of 100. "]
    if verdict.get("reasoning"):
        parts.append(verdict["reasoning"])
    nh = cal.get("next_high")
    if nh:
        parts.append(f" Watch {nh['currency']} {nh['title']} in "
                     f"{nh['in_hours']:.0f} hours.")
    parts.append(" Not financial advice.")

    return {
        "ok": True,
        "symbol": base["symbol"],
        "base": base["base"],
        "source": base["source"],
        "price": base["price"],
        "bias": base["bias"],
        "timeframes": base["timeframes"],
        "supports": base["supports"],
        "resistances": base["resistances"],
        "order_blocks": base["order_blocks"],
        "setup": base["setup"],
        "liquidity": liq,
        "calendar": cal,
        "sentiment": sent,
        "session": sess,
        "decision": verdict,
        "candles": candles,
        "speak": "".join(parts),
    }
