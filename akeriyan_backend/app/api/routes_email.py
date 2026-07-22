from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.email import gmail

router = APIRouter(prefix="/v1/email", dependencies=[Depends(verify_token)])


class SendIn(BaseModel):
    to: str
    subject: str = ""
    body: str


@router.get("/inbox")
async def inbox(limit: int = 6, unread_only: bool = True):
    """Fast — just the list (no LLM). Call /summary for the AI summary."""
    data = await gmail.inbox(limit, unread_only)
    if data["ok"]:
        n = len(data["emails"])
        data["speak"] = f"You have {n} new email{'s' if n != 1 else ''}." \
            if n else "You have no new emails."
    else:
        data["speak"] = data.get("error")
    return data


@router.get("/summary")
async def summary():
    return {"speak": await gmail.spoken_summary()}


@router.post("/send")
async def send(body: SendIn):
    return await gmail.send(body.to, body.subject or "(no subject)", body.body)
