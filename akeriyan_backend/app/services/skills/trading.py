"""Crypto market analysis — 100% free via Binance public market data.

No API key, no account. Uses data-api.binance.vision (Binance's open
market-data host) so it works from anywhere without region locks.

Fetches candles + 24h stats, computes SMA / RSI / trend, and produces both
a spoken summary (for voice) and raw candles (for the app's chart screen).
"""
import httpx

_client = httpx.AsyncClient(timeout=10.0)
_BASE = "https://data-api.binance.vision"

# Spoken names -> Binance base asset.
_COINS = {
    "bitcoin": "BTC", "btc": "BTC",
    "ethereum": "ETH", "eth": "ETH", "ether": "ETH",
    "bnb": "BNB", "binance coin": "BNB",
    "solana": "SOL", "sol": "SOL",
    "ripple": "XRP", "xrp": "XRP",
    "dogecoin": "DOGE", "doge": "DOGE",
    "cardano": "ADA", "ada": "ADA",
    "polygon": "MATIC", "matic": "MATIC",
    "litecoin": "LTC", "ltc": "LTC",
    "tron": "TRX", "trx": "TRX",
    "shiba": "SHIB", "shiba inu": "SHIB",
    "avalanche": "AVAX", "avax": "AVAX",
    "chainlink": "LINK", "link": "LINK",
    "polkadot": "DOT", "dot": "DOT",
}

# Accepted candle intervals (Binance format).
_INTERVALS = {"1m", "5m", "15m", "1h", "4h", "1d", "1w"}


def resolve_symbol(spoken: str | None) -> str | None:
    """'analyse ethereum' -> 'ETHUSDT'. Returns None if no coin is recognised."""
    if not spoken:
        return None
    s = spoken.lower().strip()
    if s.endswith("usdt") and len(s) > 4:          # already a symbol
        return s.upper()
    # longest names first ("binance coin" before "coin")
    for name, base in sorted(_COINS.items(), key=lambda kv: -len(kv[0])):
        if name in s:
            return f"{base}USDT"
    # bare ticker like "BTC"
    token = "".join(c for c in s if c.isalpha()).upper()
    if 2 <= len(token) <= 6:
        return f"{token}USDT"
    return None


def _sma(values: list[float], period: int) -> float | None:
    if len(values) < period:
        return None
    return sum(values[-period:]) / period


def _rsi(closes: list[float], period: int = 14) -> float | None:
    if len(closes) <= period:
        return None
    gains, losses = 0.0, 0.0
    for i in range(-period, 0):
        diff = closes[i] - closes[i - 1]
        if diff >= 0:
            gains += diff
        else:
            losses -= diff
    avg_gain = gains / period
    avg_loss = losses / period
    if avg_loss == 0:
        return 100.0
    rs = avg_gain / avg_loss
    return round(100 - (100 / (1 + rs)), 1)


def _ema_series(values: list[float], period: int) -> list[float]:
    if len(values) < period:
        return []
    k = 2 / (period + 1)
    ema = sum(values[:period]) / period
    out = [ema]
    for v in values[period:]:
        ema = v * k + ema * (1 - k)
        out.append(ema)
    return out


def _ema(values: list[float], period: int) -> float | None:
    s = _ema_series(values, period)
    return s[-1] if s else None


def _macd(closes: list[float]) -> dict | None:
    if len(closes) < 35:
        return None
    ema12 = _ema_series(closes, 12)
    ema26 = _ema_series(closes, 26)
    n = min(len(ema12), len(ema26))
    if n == 0:
        return None
    macd_line = [ema12[-n:][i] - ema26[-n:][i] for i in range(n)]
    signal = _ema_series(macd_line, 9)
    if not signal:
        return None
    return {"macd": round(macd_line[-1], 6),
            "signal": round(signal[-1], 6),
            "hist": round(macd_line[-1] - signal[-1], 6)}


def _bollinger(closes: list[float], period: int = 20, mult: float = 2) -> dict | None:
    if len(closes) < period:
        return None
    window = closes[-period:]
    mid = sum(window) / period
    sd = (sum((x - mid) ** 2 for x in window) / period) ** 0.5
    return {"mid": round(mid, 6),
            "upper": round(mid + mult * sd, 6),
            "lower": round(mid - mult * sd, 6)}


def _fmt(n: float) -> str:
    """Human/spoken price formatting."""
    if n >= 1000:
        return f"{n:,.0f}"
    if n >= 1:
        return f"{n:,.2f}"
    return f"{n:.6f}".rstrip("0")


async def analyze(spoken_symbol: str | None, interval: str = "1h") -> dict:
    symbol = resolve_symbol(spoken_symbol)
    if not symbol:
        return {"ok": False,
                "speak": "Which coin should I analyse? Try Bitcoin or Ethereum."}
    if interval not in _INTERVALS:
        interval = "1h"

    try:
        kl = await _client.get(f"{_BASE}/api/v3/klines",
                               params={"symbol": symbol, "interval": interval,
                                       "limit": 100})
        if kl.status_code != 200:
            return {"ok": False,
                    "speak": f"I couldn't find market data for {spoken_symbol}."}
        raw = kl.json()
        tk = await _client.get(f"{_BASE}/api/v3/ticker/24hr",
                               params={"symbol": symbol})
        stats = tk.json()
    except Exception:
        return {"ok": False,
                "speak": "I couldn't reach the market data service right now."}

    # Binance kline: [openTime, open, high, low, close, volume, ...]
    candles = [
        {"t": int(c[0]), "o": float(c[1]), "h": float(c[2]),
         "l": float(c[3]), "c": float(c[4])}
        for c in raw
    ]
    closes = [c["c"] for c in candles]
    price = float(stats.get("lastPrice", closes[-1]))
    change_pc = float(stats.get("priceChangePercent", 0.0))
    high24 = float(stats.get("highPrice", max(c["h"] for c in candles)))
    low24 = float(stats.get("lowPrice", min(c["l"] for c in candles)))

    sma20 = _sma(closes, 20)
    sma50 = _sma(closes, 50)
    rsi = _rsi(closes)

    # ---- Signal logic (simple, transparent) --------------------------------
    bull, bear = 0, 0
    if sma20 and sma50:
        if sma20 > sma50:
            bull += 1
        else:
            bear += 1
    if sma20:
        if price > sma20:
            bull += 1
        else:
            bear += 1
    if rsi is not None:
        if rsi >= 70:
            bear += 1
        elif rsi <= 30:
            bull += 1
    if change_pc > 0:
        bull += 1
    elif change_pc < 0:
        bear += 1

    if bull - bear >= 2:
        trend, signal = "bullish", "Momentum looks bullish."
    elif bear - bull >= 2:
        trend, signal = "bearish", "Momentum looks bearish."
    else:
        trend, signal = "neutral", "The market looks mixed right now."

    rsi_note = ""
    if rsi is not None:
        if rsi >= 70:
            rsi_note = f" RSI is {rsi}, approaching overbought."
        elif rsi <= 30:
            rsi_note = f" RSI is {rsi}, approaching oversold."
        else:
            rsi_note = f" RSI is {rsi}."

    direction = "up" if change_pc >= 0 else "down"
    base = symbol.replace("USDT", "")
    speak = (f"{base} is trading at {_fmt(price)} dollars, "
             f"{direction} {abs(change_pc):.1f} percent in 24 hours. "
             f"{signal}{rsi_note}")

    return {
        "ok": True,
        "symbol": symbol,
        "base": base,
        "interval": interval,
        "price": price,
        "change_pc": round(change_pc, 2),
        "high_24h": high24,
        "low_24h": low24,
        "sma20": round(sma20, 6) if sma20 else None,
        "sma50": round(sma50, 6) if sma50 else None,
        "ema9": round(_ema(closes, 9), 6) if _ema(closes, 9) else None,
        "ema21": round(_ema(closes, 21), 6) if _ema(closes, 21) else None,
        "macd": _macd(closes),
        "bollinger": _bollinger(closes),
        "rsi": rsi,
        "trend": trend,
        "candles": candles,
        "speak": speak,
    }
