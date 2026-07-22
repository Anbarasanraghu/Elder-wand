"""Stock analysis — free via Yahoo Finance's public chart endpoint (no key).

Same shape as the crypto trading skill so the app's chart screen can render
either one. A browser User-Agent is required or Yahoo returns 403.
"""
import httpx

_client = httpx.AsyncClient(
    timeout=10.0,
    headers={"User-Agent": "Mozilla/5.0 (AKERIYAN)"},
)

# A few spoken names -> ticker; anything else is treated as a raw ticker.
_NAMES = {
    "apple": "AAPL", "tesla": "TSLA", "microsoft": "MSFT", "google": "GOOGL",
    "alphabet": "GOOGL", "amazon": "AMZN", "meta": "META", "facebook": "META",
    "netflix": "NFLX", "nvidia": "NVDA", "amd": "AMD", "intel": "INTC",
    "reliance": "RELIANCE.NS", "infosys": "INFY", "tcs": "TCS.NS",
    "tata motors": "TATAMOTORS.NS", "hdfc": "HDFCBANK.NS", "wipro": "WIPRO.NS",
    "sbi": "SBIN.NS", "nifty": "^NSEI", "sensex": "^BSESN",

    # ---- Precious metals (free via Yahoo) ----
    "gold": "GC=F", "gold price": "GC=F", "xauusd": "XAUUSD=X",
    "silver": "SI=F", "platinum": "PL=F", "palladium": "PA=F",
    "copper": "HG=F", "crude": "CL=F", "crude oil": "CL=F", "oil": "CL=F",
    "brent": "BZ=F", "natural gas": "NG=F",

    # ---- Forex pairs (spoken variants -> Yahoo pair) ----
    "eurusd": "EURUSD=X", "euro dollar": "EURUSD=X", "euro to dollar": "EURUSD=X",
    "euro": "EURUSD=X",
    "gbpusd": "GBPUSD=X", "pound dollar": "GBPUSD=X", "pound": "GBPUSD=X",
    "usdjpy": "USDJPY=X", "dollar yen": "USDJPY=X", "yen": "USDJPY=X",
    "usdinr": "USDINR=X", "dollar rupee": "USDINR=X", "dollar to rupee": "USDINR=X",
    "usd to inr": "USDINR=X", "rupee": "USDINR=X", "dollar to inr": "USDINR=X",
    "eurinr": "EURINR=X", "euro rupee": "EURINR=X",
    "gbpinr": "GBPINR=X", "pound rupee": "GBPINR=X",
    "audusd": "AUDUSD=X", "usdcad": "USDCAD=X", "usdchf": "USDCHF=X",
    "dollar index": "DX-Y.NYB", "dxy": "DX-Y.NYB",
}

# Friendly spoken/display labels for symbols that aren't plain tickers.
_DISPLAY = {
    "GC=F": "Gold", "XAUUSD=X": "Gold", "SI=F": "Silver", "PL=F": "Platinum",
    "PA=F": "Palladium", "HG=F": "Copper", "CL=F": "Crude Oil", "BZ=F": "Brent",
    "NG=F": "Natural Gas",
    "EURUSD=X": "EUR/USD", "GBPUSD=X": "GBP/USD", "USDJPY=X": "USD/JPY",
    "USDINR=X": "USD/INR", "EURINR=X": "EUR/INR", "GBPINR=X": "GBP/INR",
    "AUDUSD=X": "AUD/USD", "USDCAD=X": "USD/CAD", "USDCHF=X": "USD/CHF",
    "DX-Y.NYB": "Dollar Index", "^NSEI": "Nifty 50", "^BSESN": "Sensex",
}

_RANGES = {"1d": ("5d", "15m"), "1h": ("5d", "60m"),
           "1w": ("1mo", "1d"), "1mo": ("6mo", "1d"), "1y": ("1y", "1wk")}


def resolve_ticker(spoken: str | None) -> str | None:
    if not spoken:
        return None
    s = spoken.lower().strip()
    for name, tk in sorted(_NAMES.items(), key=lambda kv: -len(kv[0])):
        if name in s:
            return tk
    token = "".join(ch for ch in spoken.strip() if ch.isalnum() or ch in ".^").upper()
    return token if 1 <= len(token) <= 12 else None


def _sma(vals: list[float], p: int) -> float | None:
    return sum(vals[-p:]) / p if len(vals) >= p else None


def _rsi(closes: list[float], p: int = 14) -> float | None:
    if len(closes) <= p:
        return None
    gains = losses = 0.0
    for i in range(-p, 0):
        d = closes[i] - closes[i - 1]
        gains += d if d > 0 else 0
        losses += -d if d < 0 else 0
    if losses == 0:
        return 100.0
    rs = (gains / p) / (losses / p)
    return round(100 - 100 / (1 + rs), 1)


async def analyze(spoken: str | None, interval: str = "1d") -> dict:
    ticker = resolve_ticker(spoken)
    if not ticker:
        return {"ok": False, "speak": "Which stock should I check? Try Apple or Tesla."}
    rng, itv = _RANGES.get(interval, ("1mo", "1d"))

    try:
        r = await _client.get(
            f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}",
            params={"range": rng, "interval": itv},
        )
        if r.status_code != 200:
            return {"ok": False, "speak": f"I couldn't find a stock called {spoken}."}
        result = r.json()["chart"]["result"][0]
    except Exception:
        return {"ok": False, "speak": "I couldn't reach the stock service right now."}

    meta = result.get("meta", {})
    q = result["indicators"]["quote"][0]
    ts = result.get("timestamp", [])
    opens, highs, lows, closes = (q.get("open") or [], q.get("high") or [],
                                  q.get("low") or [], q.get("close") or [])

    candles = []
    for i in range(len(ts)):
        o, h, l, c = (opens[i] if i < len(opens) else None,
                      highs[i] if i < len(highs) else None,
                      lows[i] if i < len(lows) else None,
                      closes[i] if i < len(closes) else None)
        if None in (o, h, l, c):
            continue
        candles.append({"t": ts[i] * 1000, "o": float(o), "h": float(h),
                        "l": float(l), "c": float(c)})
    if not candles:
        return {"ok": False, "speak": f"No recent data for {spoken}."}

    close_vals = [c["c"] for c in candles]
    price = float(meta.get("regularMarketPrice") or close_vals[-1])
    # Daily move = latest price vs the previous session's close. Yahoo's chart
    # meta has no usable previousClose (chartPreviousClose is the range start),
    # so derive it from the prior candle in the series.
    prev = meta.get("previousClose")
    if not prev:
        prev = close_vals[-2] if len(close_vals) >= 2 else close_vals[-1]
    prev = float(prev)
    change_pc = ((price - prev) / prev * 100) if prev else 0.0
    cur = meta.get("currency", "USD")
    sym = "$" if cur == "USD" else ("₹" if cur == "INR" else cur + " ")

    sma20, sma50, rsi = _sma(close_vals, 20), _sma(close_vals, 50), _rsi(close_vals)
    up = change_pc >= 0
    trend = "bullish" if change_pc > 0.3 else ("bearish" if change_pc < -0.3 else "flat")
    rsi_note = f" RSI is {rsi}." if rsi is not None else ""

    name = _DISPLAY.get(ticker, ticker)
    # Forex rates read better as a plain 4-decimal number (no currency symbol).
    price_str = f"{price:,.4f}" if ticker.endswith("=X") else f"{sym}{price:,.2f}"

    speak = (f"{name} is at {price_str}, "
             f"{'up' if up else 'down'} {abs(change_pc):.2f} percent. "
             f"Trend looks {trend}.{rsi_note}")

    return {
        "ok": True, "symbol": ticker, "base": name, "interval": interval,
        "price": price, "change_pc": round(change_pc, 2),
        "high_24h": float(meta.get("regularMarketDayHigh", max(c["h"] for c in candles))),
        "low_24h": float(meta.get("regularMarketDayLow", min(c["l"] for c in candles))),
        "sma20": round(sma20, 4) if sma20 else None,
        "sma50": round(sma50, 4) if sma50 else None,
        "rsi": rsi, "trend": trend, "currency": cur,
        "candles": candles, "speak": speak,
    }
