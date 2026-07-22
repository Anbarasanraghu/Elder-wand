from fastapi import APIRouter, Depends, Response
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.tts import piper_service

router = APIRouter(prefix="/v1", dependencies=[Depends(verify_token)])


class TTSRequest(BaseModel):
    text: str


@router.post("/tts")
async def tts(req: TTSRequest):
    """Synthesise `text` with the natural Piper voice and return WAV audio.

    Returns HTTP 204 (no content) when Piper is unavailable so the app knows to
    fall back to the phone's built-in text-to-speech.
    """
    audio = await piper_service.synthesize(req.text)
    if not audio:
        return Response(status_code=204)
    return Response(content=audio, media_type="audio/wav")
