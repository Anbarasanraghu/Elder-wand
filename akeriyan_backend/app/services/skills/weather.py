"""Weather via Open-Meteo — completely free, no API key required."""
import httpx

from app.config import settings

_client = httpx.AsyncClient(timeout=10.0)

_CODES = {
    0: "clear sky", 1: "mainly clear", 2: "partly cloudy", 3: "overcast",
    45: "foggy", 48: "rime fog", 51: "light drizzle", 53: "drizzle",
    55: "heavy drizzle", 61: "light rain", 63: "rain", 65: "heavy rain",
    71: "light snow", 73: "snow", 75: "heavy snow", 80: "rain showers",
    81: "rain showers", 82: "violent rain showers", 95: "a thunderstorm",
    96: "a thunderstorm with hail", 99: "a severe thunderstorm",
}


async def _reverse_place(lat: float, lon: float) -> str | None:
    """Turn GPS coords into a spoken place name. Free, no API key."""
    try:
        r = await _client.get(
            "https://api.bigdatacloud.net/data/reverse-geocode-client",
            params={"latitude": lat, "longitude": lon, "localityLanguage": "en"},
        )
        j = r.json()
        return (j.get("city") or j.get("locality")
                or j.get("principalSubdivision") or j.get("countryName"))
    except Exception:
        return None


async def get_weather(city: str | None = None,
                      lat: float | None = None,
                      lon: float | None = None) -> str:
    """Weather for an explicitly named city, else the device's GPS location,
    else the configured default city."""
    try:
        # 1. An explicitly named city always wins ("weather in Delhi").
        # 2. Otherwise use the phone's GPS coords if the app sent them.
        # 3. Otherwise fall back to the default city.
        if not city and lat is not None and lon is not None:
            place = await _reverse_place(lat, lon) or "your location"
        else:
            city = (city or settings.default_city).strip()
            geo = await _client.get(
                "https://geocoding-api.open-meteo.com/v1/search",
                params={"name": city, "count": 1, "language": "en"},
            )
            results = geo.json().get("results")
            if not results:
                return f"I couldn't find a place called {city}."
            loc = results[0]
            lat, lon = loc["latitude"], loc["longitude"]
            place = loc.get("name", city)

        wx = await _client.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat, "longitude": lon,
                "current": "temperature_2m,apparent_temperature,weather_code,relative_humidity_2m",
                "daily": "temperature_2m_max,temperature_2m_min",
                "timezone": "auto", "forecast_days": 1,
            },
        )
        d = wx.json()
        cur = d["current"]
        daily = d["daily"]
        desc = _CODES.get(cur["weather_code"], "unclear skies")
        temp = round(cur["temperature_2m"])
        feels = round(cur["apparent_temperature"])
        hi = round(daily["temperature_2m_max"][0])
        lo = round(daily["temperature_2m_min"][0])
        return (f"In {place} it's {temp} degrees with {desc}, feels like {feels}. "
                f"Today's high is {hi} and low is {lo}.")
    except Exception:
        return "I couldn't reach the weather service right now."
