"""Proactive morning briefing — weather + top news in one spoken summary."""
from app.config import settings
from app.services.skills import weather, news


async def morning_briefing(city: str | None = None,
                           lat: float | None = None,
                           lon: float | None = None) -> str:
    wx = await weather.get_weather(city, lat, lon)
    headlines = await news.get_news(None, limit=3)
    return (f"Good morning, {settings.owner_name}. {wx} "
            f"Now the news. {headlines}")
