"""Liquidity mapping (Smart Money Concepts) from candle data.

- Buy-side liquidity (BSL): resting stops ABOVE equal/ swing highs.
- Sell-side liquidity (SSL): resting stops BELOW equal/ swing lows.
- Equal highs/lows: obvious liquidity pools price tends to hunt.
- Liquidity sweep / stop-hunt: price spikes past a level then closes back,
  a classic reversal tell.
"""


def _swings(candles: list, w: int = 2):
    highs, lows = [], []
    for i in range(w, len(candles) - w):
        hi, lo = candles[i]["h"], candles[i]["l"]
        if all(hi > candles[j]["h"] for j in range(i - w, i)) and \
           all(hi >= candles[j]["h"] for j in range(i + 1, i + w + 1)):
            highs.append((i, hi))
        if all(lo < candles[j]["l"] for j in range(i - w, i)) and \
           all(lo <= candles[j]["l"] for j in range(i + 1, i + w + 1)):
            lows.append((i, lo))
    return highs, lows


def _equal_levels(points: list, tol: float):
    """Group swing points whose prices are within `tol` -> liquidity pools."""
    prices = sorted(p for _, p in points)
    pools = []
    i = 0
    while i < len(prices):
        grp = [prices[i]]
        j = i + 1
        while j < len(prices) and abs(prices[j] - grp[-1]) / grp[-1] <= tol:
            grp.append(prices[j])
            j += 1
        if len(grp) >= 2:  # 2+ touches = a real pool
            pools.append({"price": round(sum(grp) / len(grp), 6),
                          "touches": len(grp)})
        i = j
    return pools


def _sweep(candles: list, lookback: int = 6, ref: int = 40):
    """Detect a recent liquidity grab (spike past a level, close back)."""
    n = len(candles)
    if n < ref:
        return None
    window = candles[n - ref:n - lookback]
    if not window:
        return None
    ref_high = max(c["h"] for c in window)
    ref_low = min(c["l"] for c in window)
    for i in range(n - lookback, n):
        c = candles[i]
        if c["h"] > ref_high and c["c"] < ref_high:
            return {"type": "bearish", "level": round(ref_high, 6),
                    "desc": "swept buy-side liquidity then rejected"}
        if c["l"] < ref_low and c["c"] > ref_low:
            return {"type": "bullish", "level": round(ref_low, 6),
                    "desc": "swept sell-side liquidity then reclaimed"}
    return None


def analyze(candles: list) -> dict:
    if len(candles) < 15:
        return {"bsl": [], "ssl": [], "equal_highs": [], "equal_lows": [],
                "sweep": None}
    price = candles[-1]["c"]
    highs, lows = _swings(candles, 2)
    tol = 0.0012

    eqh = _equal_levels(highs, tol)
    eql = _equal_levels(lows, tol)

    # Buy-side liquidity = swing highs above price (nearest first).
    bsl = sorted({round(p, 6) for _, p in highs if p > price})[:4]
    # Sell-side liquidity = swing lows below price (nearest first).
    ssl = sorted({round(p, 6) for _, p in lows if p < price}, reverse=True)[:4]

    return {
        "bsl": bsl,                       # targets above
        "ssl": ssl,                       # targets below
        "equal_highs": [e for e in eqh if e["price"] > price][:3],
        "equal_lows": [e for e in eql if e["price"] < price][:3],
        "sweep": _sweep(candles),
    }
