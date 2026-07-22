"""Active FX trading session + volatility context from the current UTC time."""
from datetime import datetime, timezone


def active_session() -> dict:
    h = datetime.now(timezone.utc).hour
    sessions = []
    if 0 <= h < 9:
        sessions.append("Tokyo")
    if 7 <= h < 16:
        sessions.append("London")
    if 12 <= h < 21:
        sessions.append("New York")
    if 21 <= h or h < 6:
        sessions.append("Sydney")

    # London/NY overlap (12-16 UTC) = highest volatility.
    if "London" in sessions and "New York" in sessions:
        vol = "high"
        note = "London/New York overlap — the most active, volatile window."
    elif "London" in sessions or "New York" in sessions:
        vol = "medium"
        note = f"{' & '.join(sessions)} session — good liquidity."
    else:
        vol = "low"
        note = f"{' & '.join(sessions) or 'Off-hours'} — thinner liquidity, choppier."

    return {"active": sessions or ["Off-hours"], "volatility": vol, "note": note}
