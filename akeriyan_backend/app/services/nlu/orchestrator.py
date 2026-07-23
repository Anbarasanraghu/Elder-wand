"""The single entry point the app talks to.

Pipeline:
  1. Fast rules  -> instant answers for the common single commands.
  2. Agent/LLM   -> understands anything the rules missed AND can split one
                    sentence into several ordered actions (agentic).
  3. Fulfillment -> knowledge skills fetch real answers; contacts resolve to
                    numbers; memory facts get stored/recalled.
  4. Memory      -> remember the exchange for follow-up context.

Response is single-intent, OR {"intent": "multi", "actions": [...]} when the
request needs more than one action.
"""
import re

from app.services.nlu import fast_rules, llm_nlu
from app.services.agent import planner
from app.services.memory.session import history
from app.services.memory import store
from app.services import contacts
from app.services.skills import (weather, news, websearch, translate, calc,
                                 trading, stocks, briefing, scalp, pro)

_CONJ = re.compile(r'\b(and|then|also|after that)\b', re.I)

# Words that signal a real action/skill (vs. plain conversation). When the fast
# rules are unsure AND none of these appear, the request is just a question or
# chit-chat, so we skip the heavyweight agentic planner (which loads the whole
# intent menu as its prompt = slow) and answer directly with the lightweight
# chat model. This is the single biggest latency win for everyday questions.
_ACTION_HINT = re.compile(r'''\b(
    remind|reminder|alarm|wake\s+me|timer|set\s+a|
    call|dial|ring|phone|
    text|sms|message|whatsapp|
    open|launch|flashlight|torch|notification|notifications|
    weather|temperature|forecast|
    news|headline|headlines|briefing|brief\s+me|
    email|inbox|gmail|mail|
    lead|pipeline|client|deal|crm|
    remember|forget|note\s+that|
    translate|
    search|google|look\s+up|
    price|chart|market|stock|stocks|crypto|bitcoin|ethereum|
    buy|sell|trade|trading|analysis|analyse|analyze|scalp|watch|monitor|
    gold|silver|forex|ticker|
    routine|good\s+morning|good\s+night|leaving\s+home
)\b''', re.I | re.X)


def _looks_actionable(text: str) -> bool:
    """True if the text plausibly asks for an action/skill (needs the planner)."""
    return bool(_ACTION_HINT.search(text))


async def understand(text: str,
                     lat: float | None = None,
                     lon: float | None = None,
                     lang: str = "en") -> dict:
    """Bilingual entry point. For Tamil ('ta') input, translate to English,
    run the normal pipeline, then translate the spoken reply back to Tamil."""
    reply_lang = "ta" if lang == "ta" else "en"
    if reply_lang == "ta":
        text = await translate.to_english(text)
    result = await _process(text, lat, lon)
    if reply_lang == "ta" and result.get("speak"):
        result["speak"] = await translate.to_language(result["speak"], "Tamil")
    result["speak_lang"] = reply_lang
    return result


async def _process(text: str,
                   lat: float | None = None,
                   lon: float | None = None) -> dict:
    history.add_user(text)

    rule = fast_rules.parse(text)
    confident = rule["intent"] != "unknown" and rule["confidence"] >= 0.7
    multi_hint = bool(_CONJ.search(text))

    # "add lead ..." is one action even when it contains "and" — never split it.
    single_ok = confident and (not multi_hint or rule["intent"] == "add_lead")

    steps: list[dict]
    if single_ok:
        steps = [rule]                                   # fast single path
    elif not multi_hint and not _looks_actionable(text):
        # Plain question / chit-chat — skip the agentic planner entirely and
        # answer directly with the lightweight chat model (small prompt = fast).
        steps = [{"intent": "chat", "confidence": 0.7, "slots": {}, "speak": ""}]
    else:
        plan = await planner.plan(text)                  # agentic / LLM path
        if plan:
            steps = plan
        elif confident:
            steps = [rule]
        else:
            # No LLM and rules unsure — try a plain fallback single.
            fallback = await llm_nlu.parse_with_llm(text)
            steps = [fallback or rule]

    # Fulfill each step.
    fulfilled = [await _fulfill(dict(s), text, lat, lon) for s in steps]

    if len(fulfilled) == 1:
        result = fulfilled[0]
        history.add_assistant(result.get("speak", ""))
        return result

    # Multi-step: combine into one response the app runs in order.
    combined = " ".join(s.get("speak", "").strip()
                        for s in fulfilled if s.get("speak"))
    history.add_assistant(combined)
    return {
        "intent": "multi",
        "confidence": 0.85,
        "slots": {},
        "speak": combined,
        "actions": fulfilled,
        "source": "agent",
    }


async def _fulfill(result: dict, text: str,
                   lat: float | None = None,
                   lon: float | None = None) -> dict:
    intent = result.get("intent")
    slots = result.get("slots") or {}

    if intent == "email_summary":
        from app.services.email import gmail
        result["speak"] = await gmail.spoken_summary()

    elif intent == "add_lead":
        from app.services.crm import store as crm_store, ai as crm_ai
        raw = slots.get("raw") or text
        fields = await crm_ai.extract_lead(raw)
        lead = crm_store.add_lead(fields)
        who = lead.get("company") or lead.get("name") or "the lead"
        result["speak"] = f"Added {who} to your pipeline."

    elif intent == "weather":
        result["speak"] = await weather.get_weather(slots.get("city"), lat, lon)

    elif intent == "news":
        result["speak"] = await news.get_news(slots.get("topic"))

    elif intent == "briefing":
        result["speak"] = await briefing.morning_briefing(
            slots.get("city"), lat, lon)

    elif intent == "web_search":
        result["speak"] = await websearch.search(slots.get("query") or text)

    elif intent == "translate":
        result["speak"] = await translate.translate(
            slots.get("text") or text, slots.get("target_language"))

    elif intent == "math":
        result["speak"] = calc.calculate(slots.get("expression") or text)

    elif intent == "market_analysis":
        analysis = await trading.analyze(
            slots.get("symbol") or text, slots.get("interval") or "1h")
        result["speak"] = analysis.get("speak", "")
        result["slots"] = {**slots, "analysis": analysis}

    elif intent == "stock_analysis":
        analysis = await stocks.analyze(
            slots.get("symbol") or text, slots.get("interval") or "1d")
        result["speak"] = analysis.get("speak", "")
        result["slots"] = {**slots, "analysis": analysis}

    elif intent == "scalp_analysis":
        analysis = await scalp.analyze(slots.get("symbol") or text)
        result["speak"] = analysis.get("speak", "")
        result["slots"] = {**slots, "analysis": analysis}

    elif intent == "pro_analysis":
        analysis = await pro.analyze(slots.get("symbol") or text)
        result["speak"] = analysis.get("speak", "")
        result["slots"] = {**slots, "analysis": analysis}

    elif intent == "remember":
        fact = slots.get("fact") or store.extract_fact(text) or text
        result["speak"] = store.remember(fact)

    elif intent == "recall":
        result["speak"] = store.recall_spoken()

    elif intent == "forget":
        result["speak"] = store.forget(slots.get("query"))

    elif intent == "chat":
        if not result.get("speak"):
            result["speak"] = await llm_nlu.free_chat(text)

    elif intent == "unknown":
        result["intent"] = "chat"
        result["speak"] = await llm_nlu.free_chat(text)

    elif intent in ("phone_call", "send_sms", "whatsapp_send"):
        if not slots.get("number"):
            number = contacts.resolve(slots.get("contact"))
            if number:
                slots["number"] = number
            elif slots.get("contact"):
                result["speak"] = (result.get("speak")
                                   or f"I don't have a number saved for {slots['contact']}.")
        result["slots"] = slots

    elif intent == "set_timer":
        secs = slots.get("seconds")
        if not isinstance(secs, int):
            secs = calc.parse_seconds(text) or 0
            slots["seconds"] = secs
            result["slots"] = slots

    result.setdefault("confidence", 0.85)
    return result
