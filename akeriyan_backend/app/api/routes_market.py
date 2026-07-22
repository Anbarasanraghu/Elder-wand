from fastapi import APIRouter, Depends
from app.core.security import verify_token
from app.services.skills import trading, stocks, scalp, pro, quote

router = APIRouter(prefix="/v1/market", dependencies=[Depends(verify_token)])


@router.get("/analyze")
async def analyze(symbol: str, interval: str = "1h"):
    """Crypto analysis + candles. `symbol` may be spoken ("bitcoin") or a ticker."""
    return await trading.analyze(symbol, interval)


@router.get("/stock")
async def stock(symbol: str, interval: str = "1d"):
    """Stock analysis + candles (free Yahoo Finance). `symbol` spoken or ticker."""
    return await stocks.analyze(symbol, interval)


@router.get("/scalp")
async def scalp_setup(symbol: str):
    """Multi-timeframe scalp analysis: bias (4h/1h/15m), order blocks,
    support/resistance and a 1-minute entry setup."""
    return await scalp.analyze(symbol)


@router.get("/price")
async def price(symbol: str):
    """Fast live price for the real-time agent — poll this every few seconds."""
    return await quote.quote(symbol)


@router.get("/pro")
async def pro_analysis(symbol: str):
    """Full terminal: bias + liquidity + order blocks + support/resistance +
    economic calendar (ForexFactory) + sentiment + session + an AI decision."""
    return await pro.analyze(symbol)
