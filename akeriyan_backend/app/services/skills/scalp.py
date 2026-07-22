"""Scalping / Smart-Money analysis — multi-timeframe bias, order blocks,
support & resistance, and a 1-minute entry setup.

All from FREE candle data (Binance for crypto, Yahoo for stocks/forex/metals).
Educational analysis only — NOT financial advice.

Method:
  4H + 1H  -> higher-timeframe BIAS (trade direction)
  15m      -> structure: support/resistance + order blocks (entry zones)
  1m       -> micro trigger (timing)
"""
import asyncio
import httpx

from app.services.skills import trading, stocks

_client = httpx.AsyncClient(
    timeout=12.0, headers={"User-Agent": "Mozilla/5.0 (AKERIYAN)"})
_BINANCE = "https://data-api.binance.vision"


# ---------------------------------------------------------------- data fetch
async def _binance(symbol: str, interval: str, limit: int = 300):
    try:
        r = await _client.get(f"{_BINANCE}/api/v3/klines",
                              params={"symbol": symbol, "interval": interval,
                                      "limit": limit})
        if r.status_code != 200:
            return None
        return [{"t": int(c[0]), "o": float(c[1]), "h": float(c[2]),
                 "l": float(c[3]), "c": float(c[4])} for c in r.json()]
    except Exception:
        return None


async def _yahoo(ticker: str, rng: str, itv: str):
    try:
        r = await _client.get(
            f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}",
            params={"range": rng, "interval": itv})
        if r.status_code != 200:
            return None
        res = r.json()["chart"]["result"][0]
        ts = res.get("timestamp") or []
        q = res["indicators"]["quote"][0]
        out = []
        for i in range(len(ts)):
            o, h, l, c = (q["open"][i], q["high"][i], q["low"][i], q["close"][i])
            if None in (o, h, l, c):
                continue
            out.append({"t": ts[i] * 1000, "o": float(o), "h": float(h),
                        "l": float(l), "c": float(c)})
        return out or None
    except Exception:
        return None


def _resample(candles: list, factor: int) -> list:
    """Merge every `factor` candles into one (e.g. 1h -> 4h with factor=4)."""
    out = []
    for i in range(0, len(candles) - factor + 1, factor):
        grp = candles[i:i + factor]
        out.append({"t": grp[0]["t"], "o": grp[0]["o"],
                    "h": max(x["h"] for x in grp),
                    "l": min(x["l"] for x in grp), "c": grp[-1]["c"]})
    return out


# ------------------------------------------------------------------ analysis
def _ema(vals: list, period: int):
    if len(vals) < period:
        return None
    k = 2 / (period + 1)
    e = sum(vals[:period]) / period
    for v in vals[period:]:
        e = v * k + e * (1 - k)
    return e


def _trend(candles: list) -> str:
    closes = [c["c"] for c in candles]
    if len(closes) < 12:
        return "unclear"
    if len(closes) < 50:
        return "bullish" if closes[-1] > closes[0] else "bearish"
    e20, e50, price = _ema(closes, 20), _ema(closes, 50), closes[-1]
    if e20 > e50 and price > e50:
        return "bullish"
    if e20 < e50 and price < e50:
        return "bearish"
    return "ranging"


def _swings(candles: list, w: int = 2):
    highs, lows = [], []
    for i in range(w, len(candles) - w):
        hi, lo = candles[i]["h"], candles[i]["l"]
        if all(hi > candles[j]["h"] for j in range(i - w, i)) and \
           all(hi >= candles[j]["h"] for j in range(i + 1, i + w + 1)):
            highs.append(hi)
        if all(lo < candles[j]["l"] for j in range(i - w, i)) and \
           all(lo <= candles[j]["l"] for j in range(i + 1, i + w + 1)):
            lows.append(lo)
    return highs, lows


def _cluster(levels: list, tol: float):
    if not levels:
        return []
    levels = sorted(levels)
    clusters = [[levels[0]]]
    for p in levels[1:]:
        if abs(p - clusters[-1][-1]) / clusters[-1][-1] <= tol:
            clusters[-1].append(p)
        else:
            clusters.append([p])
    return [sum(c) / len(c) for c in clusters]


def support_resistance(candles: list):
    highs, lows = _swings(candles, 2)
    price = candles[-1]["c"]
    tol = 0.0018
    sup = _cluster(lows, tol)
    res = _cluster(highs, tol)
    supports = sorted([lv for lv in sup if lv < price], reverse=True)
    resistances = sorted([lv for lv in res if lv > price])
    return supports, resistances


def order_blocks(candles: list, lookback: int = 70):
    """Most recent unmitigated bullish & bearish order blocks.

    Bullish OB = last down candle before a bullish displacement that closes
    above the down candle's high. Bearish OB = mirror image.
    """
    n = len(candles)
    bull = bear = None
    start = max(1, n - lookback)
    for i in range(n - 2, start, -1):
        c, nxt = candles[i], candles[i + 1]
        if bull is None and c["c"] < c["o"] and nxt["c"] > c["h"]:
            bull = {"lo": c["l"], "hi": c["h"]}
        if bear is None and c["c"] > c["o"] and nxt["c"] < c["l"]:
            bear = {"lo": c["l"], "hi": c["h"]}
        if bull and bear:
            break
    return bull, bear


def _combine_bias(t4: str, t1: str) -> str:
    if t4 == "bullish" and t1 in ("bullish", "ranging", "unclear"):
        return "bullish"
    if t4 == "bearish" and t1 in ("bearish", "ranging", "unclear"):
        return "bearish"
    if t4 == t1:
        return t4
    return "neutral"


def _fmt(n: float) -> str:
    if n >= 1000:
        return f"{n:,.0f}"
    if n >= 1:
        return f"{n:,.2f}"
    return f"{n:.5f}"


def build_setup(bias, price, supports, resistances, bull_ob, bear_ob):
    if bias == "bullish":
        zone = bull_ob or (
            {"lo": supports[0] * 0.999, "hi": supports[0]} if supports else None)
        if not zone:
            return None
        entry = (zone["lo"] + zone["hi"]) / 2
        stop = zone["lo"] * 0.9975
        target = resistances[0] if resistances else price * 1.012
        if entry <= stop or target <= entry:
            return None
        rr = (target - entry) / (entry - stop)
        return {"direction": "long", "entry": [zone["lo"], zone["hi"]],
                "stop": stop, "target": target, "rr": round(rr, 2)}
    if bias == "bearish":
        zone = bear_ob or (
            {"lo": resistances[0], "hi": resistances[0] * 1.001}
            if resistances else None)
        if not zone:
            return None
        entry = (zone["lo"] + zone["hi"]) / 2
        stop = zone["hi"] * 1.0025
        target = supports[0] if supports else price * 0.988
        if entry >= stop or target >= entry:
            return None
        rr = (entry - target) / (stop - entry)
        return {"direction": "short", "entry": [zone["lo"], zone["hi"]],
                "stop": stop, "target": target, "rr": round(rr, 2)}
    return None


async def analyze(spoken: str | None) -> dict:
    """Full multi-timeframe scalp analysis for a crypto/forex/stock symbol."""
    # 1) Resolve symbol + data source.
    crypto = trading.resolve_symbol(spoken)
    source = "crypto"
    c15 = await _binance(crypto, "15m", 300) if crypto else None

    if c15:
        symbol, display = crypto, crypto.replace("USDT", "")
        # Fetch the remaining timeframes concurrently (fast).
        c4h, c1h, c1m = await asyncio.gather(
            _binance(symbol, "4h", 250),
            _binance(symbol, "1h", 250),
            _binance(symbol, "1m", 200),
        )
    else:
        source = "yahoo"
        ticker = stocks.resolve_ticker(spoken)
        if not ticker:
            return {"ok": False,
                    "speak": "Which market should I scalp? Try Bitcoin, gold or EURUSD."}
        display = stocks._DISPLAY.get(ticker, ticker)
        symbol = ticker
        # Fetch all Yahoo timeframes concurrently (much faster than serial).
        c1h, c15, c1m = await asyncio.gather(
            _yahoo(ticker, "1mo", "60m"),
            _yahoo(ticker, "5d", "15m"),
            _yahoo(ticker, "1d", "5m"),
        )
        c4h = _resample(c1h, 4) if c1h else None

    if not c15 or len(c15) < 20:
        return {"ok": False,
                "speak": f"I couldn't get enough data to scalp {spoken}."}

    price = c15[-1]["c"]
    t4 = _trend(c4h) if c4h else "unclear"
    t1 = _trend(c1h) if c1h else "unclear"
    t15 = _trend(c15)
    t1m = _trend(c1m) if c1m else "unclear"
    bias = _combine_bias(t4, t1)

    supports, resistances = support_resistance(c15)
    bull_ob, bear_ob = order_blocks(c15)
    setup = build_setup(bias, price, supports, resistances, bull_ob, bear_ob)

    # 2) Build the spoken narrative.
    parts = [f"Scalp read for {display}. "
             f"4-hour is {t4}, 1-hour is {t1}, 15-minute is {t15}. "
             f"Overall bias is {bias}."]
    if supports:
        parts.append(f" Nearest support {_fmt(supports[0])}.")
    if resistances:
        parts.append(f" Nearest resistance {_fmt(resistances[0])}.")
    ob = bull_ob if bias == "bullish" else (bear_ob if bias == "bearish" else None)
    if ob:
        parts.append(f" There's a 15-minute {bias} order block between "
                     f"{_fmt(ob['lo'])} and {_fmt(ob['hi'])}.")
    if setup:
        d = setup
        parts.append(
            f" Scalp plan: {d['direction']} from {_fmt(d['entry'][0])} to "
            f"{_fmt(d['entry'][1])}, stop {_fmt(d['stop'])}, target "
            f"{_fmt(d['target'])}, about {d['rr']} R. On the 1-minute "
            f"(currently {t1m}), wait for a {bias} break of structure to trigger.")
    else:
        parts.append(" No clean setup right now — bias is mixed, so stay patient.")
    parts.append(" This is analysis only, not financial advice.")

    return {
        "ok": True,
        "symbol": symbol,
        "base": display,
        "source": source,
        "price": price,
        "bias": bias,
        "timeframes": {"4h": t4, "1h": t1, "15m": t15, "1m": t1m},
        "supports": [round(s, 6) for s in supports[:4]],
        "resistances": [round(r, 6) for r in resistances[:4]],
        "order_blocks": {"bullish": bull_ob, "bearish": bear_ob},
        "setup": setup,
        "candles": c15[-120:],
        "speak": "".join(parts),
    }
