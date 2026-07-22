from fastapi import APIRouter, Depends, File, Form, UploadFile

from app.core.security import verify_token
from app.services.vision import moondream_service

router = APIRouter(prefix="/v1", dependencies=[Depends(verify_token)])


@router.post("/vision")
async def vision(
    image: UploadFile = File(...),
    question: str | None = Form(None),
):
    """Analyse a camera photo with the local vision model and return a spoken
    answer. `question` is optional (e.g. 'read this text', 'what is this?')."""
    data = await image.read()
    answer = await moondream_service.analyze(data, question)
    return {"speak": answer}
