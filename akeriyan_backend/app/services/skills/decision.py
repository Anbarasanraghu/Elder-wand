"""The AI trade-decision engine — the brain that ties it all together.

Takes the full picture (multi-timeframe bias, liquidity, support/resistance,
the setup, economic news, sentiment, session) and produces ONE decision:
an action (LONG / SHORT / WAIT), a 0-100 confluence score, confidence, and
plain-English reasoning + a risk note. Uses the local LLM when available,
with a transparent rule-based fallback.
"""
from app.services.llm import ollama_service


def confluence_score(ctx: dict) -> tuple[int, list[str]]:
    """Transparent 0-100 setup-quality score with the reasons behind it."""
    score = 50
    reasons = []
    tf = ctx["timeframes"]
    bias = ctx["bias"]

    # Timeframe alignment.
    aligned = sum(1 for k in ("4h", "1h", "15m") if tf.get(k) == bias)
    if bias in ("bullish", "bearish"):
        score += aligned * 8
        reasons.append(f"{aligned}/3 higher timeframes agree ({bias})")
    else:
        score -= 10
        reasons.append("timeframes disagree (no clear bias)")

    # A concrete setup with decent R:R.
    setup = ctx.get("setup")
    if setup:
        rr = setup.get("rr", 0)
        if rr >= 2:
            score += 12
            reasons.append(f"clean setup, {rr}R")
        elif rr >= 1:
            score += 5
            reasons.append(f"setup present, {rr}R")
        else:
            reasons.append(f"setup R:R is low ({rr})")
    else:
        score -= 8
        reasons.append("no clean entry setup")

    # Liquidity sweep in the bias direction is a strong tell.
    sweep = ctx.get("liquidity", {}).get("sweep")
    if sweep:
        if sweep["type"] == bias:
            score += 10
            reasons.append(f"liquidity {sweep['desc']} (with bias)")
        else:
            score -= 6
            reasons.append(f"liquidity {sweep['desc']} (against bias)")

    # News risk.
    risk = ctx.get("calendar", {}).get("news_risk", "low")
    if risk == "high":
        score -= 18
        reasons.append("HIGH-impact news imminent — elevated risk")
    elif risk == "elevated":
        score -= 8
        reasons.append("high-impact news later today")

    # Sentiment extreme (contrarian nudge for crypto).
    fng = ctx.get("sentiment", {}).get("fear_greed")
    if fng:
        if fng["value"] <= 25 and bias == "bullish":
            score += 5
            reasons.append(f"extreme fear ({fng['value']}) supports longs")
        elif fng["value"] >= 75 and bias == "bearish":
            score += 5
            reasons.append(f"extreme greed ({fng['value']}) supports shorts")

    # Session volatility.
    vol = ctx.get("session", {}).get("volatility")
    if vol == "high":
        score += 4
        reasons.append("high-volatility session")
    elif vol == "low":
        score -= 4
        reasons.append("low-liquidity session")

    return max(0, min(100, score)), reasons


def _rule_decision(ctx: dict, score: int) -> dict:
    bias = ctx["bias"]
    risk = ctx.get("calendar", {}).get("news_risk", "low")
    if risk == "high":
        action = "WAIT"
    elif bias == "bullish" and score >= 60:
        action = "LONG"
    elif bias == "bearish" and score >= 60:
        action = "SHORT"
    else:
        action = "WAIT"
    conf = "high" if score >= 72 else ("medium" if score >= 55 else "low")
    return {"action": action, "confidence": conf}


async def decide(ctx: dict) -> dict:
    score, reasons = confluence_score(ctx)
    base = _rule_decision(ctx, score)

    result = {
        "action": base["action"],
        "confidence": base["confidence"],
        "score": score,
        "reasons": reasons,
        "reasoning": "",
    }

    if not await ollama_service.is_available():
        result["reasoning"] = "; ".join(reasons) + "."
        return result

    # Let the LLM write the human verdict from the structured facts.
    setup = ctx.get("setup")
    cal = ctx.get("calendar", {})
    facts = {
        "symbol": ctx.get("base"),
        "price": ctx.get("price"),
        "bias": ctx["bias"],
        "timeframes": ctx["timeframes"],
        "confluence_score": score,
        "rule_action": base["action"],
        "setup": setup,
        "support": ctx.get("supports", [])[:2],
        "resistance": ctx.get("resistances", [])[:2],
        "liquidity_targets_above": ctx.get("liquidity", {}).get("bsl", [])[:2],
        "liquidity_targets_below": ctx.get("liquidity", {}).get("ssl", [])[:2],
        "liquidity_sweep": ctx.get("liquidity", {}).get("sweep"),
        "news_risk": cal.get("news_risk"),
        "next_high_impact_news": (cal.get("next_high") or {}).get("title"),
        "fear_greed": (ctx.get("sentiment", {}).get("fear_greed") or {}).get("label"),
        # Only headline titles, trimmed, to keep the prompt small (= faster).
        "headlines": (ctx.get("sentiment", {}).get("news", {}).get("summary") or "")[:400],
        "session_volatility": ctx.get("session", {}).get("volatility"),
    }
    try:
        raw = await ollama_service.chat_json([
            {"role": "system",
             "content": "You are Elder Wand, a disciplined trading co-pilot. "
                        "Given market facts, return ONLY compact JSON "
                        '{"action":"LONG|SHORT|WAIT","confidence":"low|medium|high",'
                        '"news_mood":"bullish|bearish|neutral",'
                        '"verdict":"2 short spoken sentences: the plan + main risk"}. '
                        "If high-impact news is imminent, prefer WAIT. Be concise."},
            {"role": "user", "content": str(facts)},
        ], max_tokens=170)
        act = (raw.get("action") or base["action"]).upper()
        if act in ("LONG", "SHORT", "WAIT"):
            result["action"] = act
        result["confidence"] = raw.get("confidence") or base["confidence"]
        result["reasoning"] = raw.get("verdict") or "; ".join(reasons)
        mood = (raw.get("news_mood") or "neutral").lower()
        result["news_mood"] = mood if mood in ("bullish", "bearish", "neutral") else "neutral"
    except Exception:
        result["reasoning"] = "; ".join(reasons) + "."
    return result
