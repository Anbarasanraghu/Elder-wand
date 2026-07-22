from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.meeting import summarize as meeting

router = APIRouter(prefix="/v1/meeting", dependencies=[Depends(verify_token)])


class TranscriptIn(BaseModel):
    transcript: str


@router.post("/summarize")
async def summarize(body: TranscriptIn):
    """Transcript -> {summary, action_items}. The app records + sends audio to
    /v1/stt first, then posts the transcript here."""
    return await meeting.summarize(body.transcript)
