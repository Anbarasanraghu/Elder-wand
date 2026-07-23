"""LLM-powered understanding — the part that makes AKERIYAN feel intelligent.

Fast rules ([fast_rules.py]) handle the common, zero-latency commands.
Whatever they can't confidently classify comes here, where the local model
maps free-form speech onto one of AKERIYAN's intents (or just chats back).
"""
from app.config import settings
from app.services.llm import ollama_service
from app.services.memory.session import history
from app.services.memory import store

# The menu of things AKERIYAN can do. The model must pick exactly one.
INTENT_MENU = """
create_reminder   slots: text, time (natural language like "8 pm" / "in 10 minutes"), recurrence ("daily" or null)
set_timer         slots: seconds (integer)
open_app          slots: app (app name)
phone_call        slots: contact (person's name)
send_sms          slots: contact, message
whatsapp_send     slots: contact, message
read_notifications slots: kind ("latest" or "all")
toggle_flashlight slots: state ("on" or "off")
routine           slots: name ("good_morning" | "good_night" | "leaving_home")
remember          slots: fact (the thing to remember about the user)
recall            slots: (none)
forget            slots: query (what to forget, or "everything")
briefing          slots: (none — a morning briefing)
weather           slots: city (or null for the default city)
market_analysis   slots: symbol (a crypto coin like "bitcoin" / "ethereum"), interval ("1h"/"4h"/"1d")
stock_analysis    slots: symbol (a stock ticker "AAPL"/"INFY", a commodity "gold"/"silver"/"crude oil", or a forex pair "EURUSD"/"USDINR")
scalp_analysis    slots: symbol (any market) — multi-timeframe scalp setup: 4h/1h/15m bias, order blocks, support/resistance, 1-minute entry
pro_analysis      slots: symbol (any market) — FULL terminal: liquidity, economic news, sentiment, session + an AI buy/sell/wait decision. Use when the user asks "should I buy/sell", "full analysis", "liquidity", or "your decision"
watch_market      slots: symbol (any market) — open the REAL-TIME live agent that streams price and alerts on entries/stops/targets. Use for "watch", "monitor", "keep an eye on", "live"
news              slots: topic (or null for top headlines)
web_search        slots: query
translate         slots: text, target_language
math              slots: expression
chat              slots: (none — you answer the question yourself in "speak")
smalltalk         slots: (none)
"""


def _system_prompt() -> str:
    return f"""You are AKERIYAN, {settings.owner_name}'s personal voice assistant.
You are witty, warm and concise, and you call the user by name occasionally.
{store.facts_context()}
Decide what the user wants and reply with ONE JSON object, nothing else:
{{"intent": "<one intent>", "slots": {{...}}, "speak": "<what to say out loud>"}}

Available intents and their slots:
{INTENT_MENU}

Rules:
- Pick the single best intent. If it's just a question or general talk, use "chat"
  and put the full spoken answer in "speak".
- For time, keep the user's natural phrasing in the "time" slot (e.g. "8 pm",
  "in 15 minutes") — do NOT convert to a timestamp.
- "speak" must be short, natural spoken English (this is read aloud by TTS).
- Never invent contacts or numbers. Just put the spoken name in "contact".
- Output MUST be valid JSON. No markdown, no extra text.
"""


async def parse_with_llm(text: str) -> dict | None:
    """Return an intent dict, or None if the LLM is unavailable."""
    if not await ollama_service.is_available():
        return None

    messages = [{"role": "system", "content": _system_prompt()}]
    messages += history.as_messages()          # conversation context
    messages.append({"role": "user", "content": text})

    data = await ollama_service.chat_json(messages, max_tokens=200)
    intent = data.get("intent")
    if not intent:
        return None

    return {
        "intent": intent,
        "confidence": 0.85,
        "slots": data.get("slots") or {},
        "speak": data.get("speak") or "",
        "source": "llm",
    }


async def free_chat(text: str) -> str:
    """Pure conversational answer (used for the 'chat' intent / fallback)."""
    if not await ollama_service.is_available():
        return "My AI brain is offline right now. Start Ollama on the PC and I'll be much smarter."
    messages = [
        {"role": "system",
         "content": f"You are Elder Wand, {settings.owner_name}'s friendly voice "
                    f"assistant. Reply in ONE or TWO short spoken sentences — "
                    f"concise and natural. No lists, no markdown."
                    + store.facts_context()},
    ]
    messages += history.as_messages()
    messages.append({"role": "user", "content": text})
    try:
        # Cap generation: spoken answers are short, and every token is CPU time.
        return await ollama_service.chat(messages, temperature=0.6, max_tokens=120)
    except Exception:
        return "Sorry, I couldn't think of an answer just now."
