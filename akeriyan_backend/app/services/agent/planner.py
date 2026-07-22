"""Agentic planner — turns ONE sentence into an ordered list of actions.

"Text Amma I'll be late and remind me to call her at 8" ->
  [ {whatsapp_send ...}, {create_reminder ...} ]

This is what makes AKERIYAN an agent rather than a single-command bot.
Falls back cleanly to a single step (or None) when the LLM is unavailable.
"""
from app.config import settings
from app.services.llm import ollama_service
from app.services.nlu.llm_nlu import INTENT_MENU
from app.services.memory.session import history
from app.services.memory import store


def _planner_system() -> str:
    return f"""You are the planner for AKERIYAN, {settings.owner_name}'s voice assistant.
{store.facts_context()}
Break the user's request into an ordered list of steps. Each step is exactly
one intent from the menu below. Most requests are a SINGLE step — only produce
multiple steps when the user clearly asks for more than one action
(e.g. joined by "and" / "then" / "also").

Reply with ONE JSON object, nothing else:
{{"steps": [{{"intent": "<intent>", "slots": {{...}}, "speak": "<short line to say>"}}]}}

Available intents and their slots:
{INTENT_MENU}

Rules:
- Keep the user's natural time phrasing in the "time" slot ("8 pm", "in 10 minutes").
- For questions / general talk use intent "chat" and answer in "speak".
- Never invent phone numbers; put the spoken name in "contact".
- Output MUST be valid JSON only.
"""


async def plan(text: str) -> list[dict] | None:
    """Return a list of step dicts, or None if the LLM can't be reached."""
    if not await ollama_service.is_available():
        return None

    messages = [{"role": "system", "content": _planner_system()}]
    messages += history.as_messages()
    messages.append({"role": "user", "content": text})

    data = await ollama_service.chat_json(messages)
    steps = data.get("steps")
    if not isinstance(steps, list) or not steps:
        return None

    cleaned: list[dict] = []
    for s in steps:
        if not isinstance(s, dict) or not s.get("intent"):
            continue
        cleaned.append({
            "intent": s["intent"],
            "slots": s.get("slots") or {},
            "speak": s.get("speak") or "",
        })
    return cleaned or None
