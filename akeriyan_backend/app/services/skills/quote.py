"""Ultra-light live price quote for the real-time agent (fast, no analysis).

Crypto -> Binance 24h ticker; everything else -> Yahoo 1-minute chart meta.
Designed to be polled every few seconds, so it does the minimum work.
"""
import httpx

from app.services.skills import trading, stocks

_client = httpx.AsyncClient(
    timeout=6.0, headers={"User-Agent": "Mozilla/5.0 (AKERIYAN)"})
_BINANCE = "https://data-api.binance.vision"


async def quote(spoken: str | None) -> dict:
    sym = trading.resolve_symbol(spoken)
    if sym:
        try:
            r = await _client.get(f"{_BINANCE}/api/v3/ticker/24hr",
                                  params={"symbol": sym})
            if r.status_code == 200:
                d = r.json()
                return {"ok": True, "symbol": sym, "base": sym.replace("USDT", ""),
                        "price": float(d["lastPrice"]),
                        "change_pc": round(float(d["priceChangePercent"]), 2),
                        "high": float(d["highPrice"]), "low": float(d["lowPrice"])}
        except Exception:
            pass

    ticker = stocks.resolve_ticker(spoken)
    if not ticker:
        return {"ok": False}
    try:
        r = await _client.get(
            f"https://query1.finance.yahoo.com/v8/finance/chart/{ticker}",
            params={"range": "1d", "interval": "1m"})
        meta = r.json()["chart"]["result"][0]["meta"]
        price = float(meta.get("regularMarketPrice"))
        prev = float(meta.get("previousClose") or meta.get("chartPreviousClose") or price)
        return {"ok": True, "symbol": ticker,
                "base": stocks._DISPLAY.get(ticker, ticker),
                "price": price,
                "change_pc": round((price - prev) / prev * 100, 2) if prev else 0.0,
                "high": float(meta.get("regularMarketDayHigh", price)),
                "low": float(meta.get("regularMarketDayLow", price)),
                "currency": meta.get("currency", "USD")}
    except Exception:
        return {"ok": False}
