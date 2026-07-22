import asyncio

from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from app.config import settings
from app.core.security import verify_token
from app.api.routes_stt import router as stt_router
from app.api.routes_nlu import router as nlu_router
from app.api.routes_market import router as market_router
from app.api.routes_tts import router as tts_router
from app.api.routes_vision import router as vision_router
from app.api.routes_crm import router as crm_router
from app.api.routes_alerts import router as alerts_router
from app.api.routes_projects import router as projects_router
from app.api.routes_meeting import router as meeting_router
from app.api.routes_rag import router as rag_router
from app.api.routes_email import router as email_router
from app.services.llm import ollama_service
from app.services.alerts import checker

app = FastAPI(title=settings.app_name, version=settings.version)

# Allow the Flutter web build (running in a browser on localhost) to call the
# backend cross-origin. Wide-open is fine for a personal LAN dev backend that
# already requires a device token on protected routes.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(stt_router)
app.include_router(nlu_router)
app.include_router(market_router)
app.include_router(tts_router)
app.include_router(vision_router)
app.include_router(crm_router)
app.include_router(alerts_router)
app.include_router(projects_router)
app.include_router(meeting_router)
app.include_router(rag_router)
app.include_router(email_router)


async def _alerts_loop():
    """Evaluate price/RSI alerts + the daily briefing every few minutes."""
    while True:
        try:
            await checker.check_all()
        except Exception as e:  # noqa: BLE001
            print(f"[AKERIYAN] alerts loop error: {e}")
        await asyncio.sleep(240)  # 4 minutes


@app.on_event("startup")
async def _start_background():
    asyncio.create_task(_alerts_loop())

@app.get("/v1/health")
async def health():
    brain = await ollama_service.is_available()
    return {
        "status": "ok",
        "app": settings.app_name,
        "version": settings.version,
        "ai_brain": "online" if brain else "offline (using fast rules)",
    }


@app.get("/v1/hello", dependencies=[Depends(verify_token)])
async def hello():
    brain = await ollama_service.is_available()
    extra = "My AI brain is online." if brain else "Running on fast rules — start Ollama for full smarts."
    return {"message": f"Yes, {settings.owner_name}. Elder Wand backend is online. {extra}"}
