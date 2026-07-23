import base64
import json

from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.nlu import orchestrator
from app.services.nlu.orchestrator import understand
from app.services.nlu import fast_rules, llm_nlu
from app.services.tts import piper_service
from app.services.memory.session import history
from app.services.memory import store
from app.services.skills import briefing, translate

router = APIRouter(prefix="/v1", dependencies=[Depends(verify_token)])


class NLURequest(BaseModel):
    text: str
    lat: float | None = None   # device GPS, so weather/briefing use where you are
    lon: float | None = None
    lang: str = "en"           # 'ta' -> reply in Tamil


@router.post("/nlu/parse")
async def nlu_parse(req: NLURequest):
    """Full brain: fast rules -> LLM -> skill fulfillment -> spoken reply."""
    try:
        return await understand(req.text, req.lat, req.lon, req.lang)
    except Exception as e:
        print(f"[AKERIYAN] NLU error on '{req.text}': {e}")
        return {
            "intent": "unknown",
            "confidence": 0.0,
            "slots": {"text": req.text},
            "speak": "Sorry, I had trouble understanding that. Please try again.",
        }


def _looks_chat(text: str) -> bool:
    """True when the request is plain conversation the LLM answers itself — the
    only path worth streaming. Mirrors orchestrator's fast-chat routing."""
    rule = fast_rules.parse(text)
    confident = rule["intent"] != "unknown" and rule["confidence"] >= 0.7
    multi = bool(orchestrator._CONJ.search(text))
    single_ok = confident and (not multi or rule["intent"] == "add_lead")
    return (not single_ok and not multi
            and not orchestrator._looks_actionable(text))


@router.post("/converse/stream")
async def converse_stream(req: NLURequest):
    """Streaming turn. For plain chat (English), streams the reply sentence by
    sentence as {"type":"audio"} WAV chunks so the app speaks the first sentence
    within ~1-2s. Everything else (actions, multi-step, Tamil) falls back to one
    {"type":"result", ...} event identical to /nlu/parse, which the app handles
    exactly as before. Newline-delimited JSON (application/x-ndjson)."""

    def ev(obj: dict) -> str:
        return json.dumps(obj) + "\n"

    async def gen():
        try:
            en_text = req.text
            if req.lang == "ta":
                en_text = await translate.to_english(req.text)

            # Only English plain-chat streams; else defer to full understand().
            if req.lang != "ta" and _looks_chat(en_text):
                history.add_user(req.text)
                yield ev({"type": "meta", "intent": "chat"})
                full = ""
                seq = 0
                async for sent in llm_nlu.free_chat_stream(en_text):
                    full = f"{full} {sent}".strip()
                    yield ev({"type": "text", "delta": sent})
                    audio = await piper_service.synthesize(sent)
                    if audio:
                        yield ev({"type": "audio", "seq": seq,
                                  "b64": base64.b64encode(audio).decode()})
                        seq += 1
                history.add_assistant(full)
                yield ev({"type": "done", "speak": full, "intent": "chat",
                          "slots": {}, "speak_lang": "en"})
            else:
                result = await understand(req.text, req.lat, req.lon, req.lang)
                # App runs its own _handleIntent + TTS for these, so no audio here.
                yield ev({"type": "result", **result})
                yield ev({"type": "done"})
        except Exception as e:  # noqa: BLE001
            print(f"[AKERIYAN] converse stream error: {e}")
            yield ev({"type": "error", "speak":
                      "Sorry, I had trouble with that. Please try again."})

    return StreamingResponse(gen(), media_type="application/x-ndjson")


class ChatRequest(BaseModel):
    text: str


@router.post("/chat")
async def chat(req: ChatRequest):
    """Pure conversational Q&A (used by the app's chat box, if any)."""
    reply = await llm_nlu.free_chat(req.text)
    return {"speak": reply}


@router.post("/memory/clear")
async def clear_memory():
    """Forget the current conversation context (not the long-term facts)."""
    history.clear()
    return {"status": "cleared"}


@router.get("/memory/facts")
async def get_facts():
    """List the long-term facts AKERIYAN remembers about you."""
    return {"facts": store.all_facts()}


@router.get("/briefing")
async def get_briefing():
    """Proactive morning briefing: weather + top news, ready to speak."""
    return {"speak": await briefing.morning_briefing()}
