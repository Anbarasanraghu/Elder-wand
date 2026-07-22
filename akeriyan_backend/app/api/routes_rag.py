import io

from fastapi import APIRouter, Depends, File, Form, UploadFile
from pydantic import BaseModel

from app.core.security import verify_token
from app.services.rag import engine, store

router = APIRouter(prefix="/v1/docs", dependencies=[Depends(verify_token)])


class AskIn(BaseModel):
    question: str


class TextDocIn(BaseModel):
    name: str
    text: str


def _pdf_text(data: bytes) -> str:
    try:
        from pypdf import PdfReader
        reader = PdfReader(io.BytesIO(data))
        return "\n".join((p.extract_text() or "") for p in reader.pages)
    except Exception as e:  # noqa: BLE001
        print(f"[AKERIYAN] pdf parse error: {e}")
        return ""


@router.post("/ingest")
async def ingest(
    file: UploadFile = File(...),
):
    """Ingest a .pdf or .txt document into the knowledge base."""
    data = await file.read()
    name = file.filename or "document"
    if name.lower().endswith(".pdf"):
        text = _pdf_text(data)
    else:
        text = data.decode("utf-8", errors="ignore")
    added = await engine.ingest(name, text)
    return {"doc": name, "chunks": added}


@router.post("/ingest_text")
async def ingest_text(body: TextDocIn):
    """Ingest pasted text as a document."""
    added = await engine.ingest(body.name, body.text)
    return {"doc": body.name, "chunks": added}


@router.get("")
async def list_docs():
    return {"docs": store.list_docs()}


@router.delete("/{doc}")
async def delete_doc(doc: str):
    return {"deleted_chunks": store.delete_doc(doc)}


@router.post("/ask")
async def ask(body: AskIn):
    return await engine.ask(body.question)
