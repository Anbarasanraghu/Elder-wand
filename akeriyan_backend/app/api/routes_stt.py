import os
import tempfile

from fastapi import APIRouter, Depends, UploadFile, File, HTTPException
from app.core.security import verify_token
from app.services.stt.whisper_service import transcribe_file

router = APIRouter(prefix="/v1", dependencies=[Depends(verify_token)])


@router.post("/stt")
async def speech_to_text(audio: UploadFile = File(...)):
    suffix = os.path.splitext(audio.filename or "audio.m4a")[1] or ".m4a"
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as tmp:
            tmp.write(await audio.read())
            tmp_path = tmp.name
        result = transcribe_file(tmp_path)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Transcription failed: {e}")
    finally:
        # Privacy: never keep audio after transcription
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)