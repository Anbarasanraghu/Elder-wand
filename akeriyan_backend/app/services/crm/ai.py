"""AI helpers for the CRM, all via the local free LLM (Ollama).

- extract_lead:   pull a clean lead record out of messy text / an email.
- score_lead:     hot / warm / cold with a one-line reason.
- draft_outreach: a personalised opener for a lead (email / whatsapp / dm).
- pipeline_insights: a spoken summary of the whole pipeline.
Every function degrades gracefully if the LLM is unavailable.
"""
from app.config import settings
from app.services.llm import ollama_service

_AGENCY = (
    f"{settings.owner_name} runs an IT agency that builds websites, mobile apps, "
    "and business automations for clients."
)


async def extract_lead(text: str) -> dict:
    """Parse a messy inquiry/message into structured lead fields."""
    if not await ollama_service.is_available():
        return {"name": "", "company": "", "notes": text.strip()}
    messages = [
        {"role": "system", "content": (
            f"{_AGENCY} Extract a sales lead from the user's text. "
            "Reply with ONE JSON object only, keys: name, company, email, phone, "
            "source, service (one of: website, app, automation, other), "
            "value (number, estimated project value or 0), notes. "
            "Use empty string/0 when unknown.")},
        {"role": "user", "content": text},
    ]
    data = await ollama_service.chat_json(messages, max_tokens=300)
    return data if isinstance(data, dict) else {"notes": text.strip()}


async def score_lead(lead: dict) -> dict:
    """Return {'score': hot|warm|cold, 'reason': '...'}"""
    if not await ollama_service.is_available():
        return {"score": lead.get("score") or "warm", "reason": ""}
    messages = [
        {"role": "system", "content": (
            f"{_AGENCY} Score this lead as hot, warm, or cold based on fit, "
            "budget signals, service match and engagement. Reply ONE JSON object: "
            '{"score":"hot|warm|cold","reason":"<short>"}')},
        {"role": "user", "content": str(lead)},
    ]
    data = await ollama_service.chat_json(messages, max_tokens=120)
    score = (data.get("score") or "warm").lower()
    if score not in ("hot", "warm", "cold"):
        score = "warm"
    return {"score": score, "reason": data.get("reason") or ""}


async def draft_outreach(lead: dict, channel: str = "email") -> str:
    """A short, personalised outreach opener for the lead."""
    if not await ollama_service.is_available():
        return "Start Ollama to generate outreach messages."
    messages = [
        {"role": "system", "content": (
            f"{_AGENCY} Write a short, friendly {channel} opener to this lead. "
            "Reference their company and the service they might need. "
            "No fluff, 3-4 sentences, end with a soft call to action. "
            "Return only the message text.")},
        {"role": "user", "content": str(lead)},
    ]
    return await ollama_service.chat(messages, temperature=0.7, max_tokens=250)


def _as_lines(items: list) -> list[str]:
    out = []
    for it in items:
        if isinstance(it, str):
            out.append(it)
        elif isinstance(it, dict):
            parts = [str(v) for v in it.values()
                     if isinstance(v, (str, int, float)) and str(v).strip()]
            if parts:
                out.append(" — ".join(parts))
    return out


def _parse_pricing(pricing) -> list[dict]:
    rows = pricing if isinstance(pricing, list) else (
        [pricing] if isinstance(pricing, dict) else [])
    out = []
    for r in rows:
        if not isinstance(r, dict):
            continue
        item = r.get("item") or r.get("name") or r.get("description") or ""
        amt = r.get("amount") or r.get("price") or r.get("cost") or 0
        try:
            amt = float(amt)
        except (TypeError, ValueError):
            amt = 0
        if item:
            out.append({"item": str(item), "amount": amt})
    return out


async def draft_proposal(lead: dict) -> dict:
    """Structured proposal the app renders as a PDF."""
    fallback = {
        "title": f"Proposal for {lead.get('company') or lead.get('name') or 'Client'}",
        "summary": "", "scope": [], "timeline": [],
        "pricing": [{"item": lead.get("service") or "Project",
                     "amount": lead.get("value") or 0}],
        "total": lead.get("value") or 0, "terms": "",
    }
    if not await ollama_service.is_available():
        return fallback
    messages = [
        {"role": "system", "content": (
            f"{_AGENCY} Draft a client proposal. Reply ONE JSON object only: "
            '{"title":"","summary":"","scope":["..."],"timeline":["..."],'
            '"pricing":[{"item":"","amount":0}],"total":0,"terms":""}. '
            "Amounts are plain INR numbers; base the total near the lead's value "
            "if provided. 3-5 scope items, 3-4 timeline phases.")},
        {"role": "user", "content": str(lead)},
    ]
    data = await ollama_service.chat_json(messages, max_tokens=700)
    if not isinstance(data, dict):
        return fallback
    out = {**fallback}
    if data.get("title"):
        out["title"] = str(data["title"])
    if data.get("summary"):
        out["summary"] = str(data["summary"])
    if isinstance(data.get("scope"), list):
        out["scope"] = _as_lines(data["scope"])
    if isinstance(data.get("timeline"), list):
        out["timeline"] = _as_lines(data["timeline"])
    pricing = _parse_pricing(data.get("pricing"))
    if pricing:
        out["pricing"] = pricing
        out["total"] = round(sum(p["amount"] for p in pricing))
    if data.get("terms"):
        out["terms"] = str(data["terms"])
    return out


async def pipeline_insights(leads: list[dict], stats: dict) -> str:
    """A concise spoken summary of the pipeline: what's working / stuck."""
    if not await ollama_service.is_available():
        return (f"You have {stats['total']} leads, {stats['by_stage'].get('won',0)} won, "
                f"pipeline value {stats['pipeline_value']}.")
    messages = [
        {"role": "system", "content": (
            f"{_AGENCY} You are the sales analyst. Give a concise, spoken 3-4 sentence "
            "summary of the pipeline: momentum, what's stuck, which source converts "
            "best, and the single most important next action. Plain sentences.")},
        {"role": "user", "content": f"stats={stats}\nleads={leads}"},
    ]
    return await ollama_service.chat(messages, temperature=0.5, max_tokens=250)
