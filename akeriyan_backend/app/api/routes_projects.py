from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.projects import store
from app.services.crm import store as crm_store

router = APIRouter(prefix="/v1/projects", dependencies=[Depends(verify_token)])


class ProjectIn(BaseModel):
    name: str | None = None
    company: str | None = None
    service: str | None = None
    status: str | None = None
    milestones: list | None = None
    deadline: str | None = None
    notes: str | None = None
    value: float | None = None


@router.post("")
async def create(p: ProjectIn):
    return store.add_project(p.model_dump(exclude_none=True))


@router.get("")
async def list_all():
    return {"projects": store.list_projects()}


@router.get("/{pid}")
async def get(pid: int):
    proj = store.get_project(pid)
    if not proj:
        raise HTTPException(404, "Project not found")
    return proj


@router.patch("/{pid}")
async def update(pid: int, p: ProjectIn):
    proj = store.update_project(pid, p.model_dump(exclude_none=True))
    if not proj:
        raise HTTPException(404, "Project not found")
    return proj


@router.delete("/{pid}")
async def delete(pid: int):
    return {"deleted": store.delete_project(pid)}


@router.post("/from_lead/{lead_id}")
async def from_lead(lead_id: int):
    """Turn a won CRM lead into a project (and mark the lead won)."""
    lead = crm_store.get_lead(lead_id)
    if not lead:
        raise HTTPException(404, "Lead not found")
    crm_store.update_lead(lead_id, {"stage": "won"})
    return store.add_project({
        "name": lead.get("name"),
        "company": lead.get("company"),
        "service": lead.get("service"),
        "value": lead.get("value"),
        "notes": lead.get("notes"),
    })
