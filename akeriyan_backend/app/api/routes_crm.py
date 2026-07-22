from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.crm import store, ai

router = APIRouter(prefix="/v1/crm", dependencies=[Depends(verify_token)])


class LeadIn(BaseModel):
    name: str | None = None
    company: str | None = None
    email: str | None = None
    phone: str | None = None
    source: str | None = None
    service: str | None = None
    value: float | None = None
    stage: str | None = None
    score: str | None = None
    notes: str | None = None
    next_followup: str | None = None


class TextIn(BaseModel):
    text: str


# ---- CRUD -----------------------------------------------------------------
@router.post("/leads")
async def create_lead(lead: LeadIn):
    return store.add_lead(lead.model_dump(exclude_none=True))


@router.get("/leads")
async def list_leads(stage: str | None = None):
    return {"leads": store.list_leads(stage)}


@router.get("/leads/{lead_id}")
async def get_lead(lead_id: int):
    lead = store.get_lead(lead_id)
    if not lead:
        raise HTTPException(404, "Lead not found")
    return lead


@router.patch("/leads/{lead_id}")
async def update_lead(lead_id: int, lead: LeadIn):
    updated = store.update_lead(lead_id, lead.model_dump(exclude_none=True))
    if not updated:
        raise HTTPException(404, "Lead not found")
    return updated


@router.delete("/leads/{lead_id}")
async def delete_lead(lead_id: int):
    return {"deleted": store.delete_lead(lead_id)}


# ---- Analytics dashboard --------------------------------------------------
@router.get("/analytics")
async def analytics():
    return store.analytics()


# ---- AI actions -----------------------------------------------------------
@router.post("/extract")
async def extract(body: TextIn):
    """Pull structured lead fields from messy text (does not save)."""
    return await ai.extract_lead(body.text)


@router.post("/import")
async def bulk_import(body: TextIn):
    """Bulk create from pasted CSV-ish lines:
    name, company, service, value, source, phone, email (extra cols optional)."""
    created = 0
    cols = ["name", "company", "service", "value", "source", "phone", "email"]
    for line in body.text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split(",")]
        data = {cols[i]: parts[i] for i in range(min(len(parts), len(cols)))}
        if data.get("name") or data.get("company"):
            store.add_lead(data)
            created += 1
    return {"created": created}


@router.post("/leads/{lead_id}/score")
async def score(lead_id: int):
    lead = store.get_lead(lead_id)
    if not lead:
        raise HTTPException(404, "Lead not found")
    result = await ai.score_lead(lead)
    store.update_lead(lead_id, {"score": result["score"]})
    return result


@router.post("/leads/{lead_id}/outreach")
async def outreach(lead_id: int, channel: str = "email"):
    lead = store.get_lead(lead_id)
    if not lead:
        raise HTTPException(404, "Lead not found")
    return {"message": await ai.draft_outreach(lead, channel)}


@router.post("/leads/{lead_id}/proposal")
async def proposal(lead_id: int):
    lead = store.get_lead(lead_id)
    if not lead:
        raise HTTPException(404, "Lead not found")
    return await ai.draft_proposal(lead)


@router.get("/insights")
async def insights():
    leads = store.list_leads()
    stats = store.analytics()
    return {"speak": await ai.pipeline_insights(leads, stats)}
