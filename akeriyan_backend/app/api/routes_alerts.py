from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.alerts import store

router = APIRouter(prefix="/v1/alerts", dependencies=[Depends(verify_token)])


class RuleIn(BaseModel):
    symbol: str
    kind: str = "price"        # 'price' or 'rsi'
    op: str = "above"          # 'above' or 'below'
    threshold: float
    note: str | None = None


class TimeIn(BaseModel):
    time: str                  # 'HH:MM' or '' to disable


@router.post("")
async def create_rule(rule: RuleIn):
    return store.add_rule(rule.model_dump())


@router.get("")
async def list_rules():
    return {"rules": store.list_rules(), "briefing_time": store.get_setting("briefing_time", "")}


@router.delete("/{rule_id}")
async def delete_rule(rule_id: int):
    return {"deleted": store.delete_rule(rule_id)}


@router.get("/pending")
async def pending():
    """The app polls this; returns undelivered notifications and marks them sent."""
    return {"pending": store.take_pending()}


@router.post("/briefing_time")
async def set_briefing_time(body: TimeIn):
    store.set_setting("briefing_time", body.time.strip())
    return {"briefing_time": body.time.strip()}
