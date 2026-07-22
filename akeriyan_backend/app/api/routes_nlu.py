from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.nlu.orchestrator import understand
from app.services.nlu import llm_nlu
from app.services.memory.session import history
from app.services.memory import store
from app.services.skills import briefing

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
