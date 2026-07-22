"""RAG engine — embed, ingest (chunk+embed+store), and ask (retrieve+answer).

Embeddings via Ollama `nomic-embed-text`; answers via the chat model. All local.
"""
import numpy as np
import httpx

from app.config import settings
from app.services.llm import ollama_service
from app.services.rag import store

_client = httpx.AsyncClient(timeout=httpx.Timeout(60.0, connect=5.0))
_EMBED_MODEL = "nomic-embed-text"


async def embed(text: str) -> list[float] | None:
    try:
        r = await _client.post(
            f"{settings.ollama_url}/api/embeddings",
            json={"model": _EMBED_MODEL, "prompt": text},
        )
        r.raise_for_status()
        return r.json().get("embedding")
    except Exception as e:  # noqa: BLE001
        print(f"[AKERIYAN] embed error: {e}")
        return None


def _chunk(text: str, size: int = 900, overlap: int = 150) -> list[str]:
    text = " ".join(text.split())
    if not text:
        return []
    chunks, i = [], 0
    while i < len(text):
        chunks.append(text[i:i + size])
        i += size - overlap
    return chunks


async def ingest(doc: str, text: str) -> int:
    chunks = _chunk(text)
    added = 0
    for ch in chunks:
        vec = await embed(ch)
        if vec:
            store.add_chunk(doc, ch, vec)
            added += 1
    return added


async def ask(question: str, k: int = 4) -> dict:
    qvec = await embed(question)
    rows = store.all_chunks()
    if not qvec or not rows:
        return {"answer": "I don't have any documents to answer from yet.",
                "sources": []}
    q = np.array(qvec, dtype=np.float32)
    mat = np.array([r["embedding"] for r in rows], dtype=np.float32)
    # cosine similarity
    sims = mat @ q / (np.linalg.norm(mat, axis=1) * np.linalg.norm(q) + 1e-8)
    top = sims.argsort()[::-1][:k]
    context = "\n\n".join(f"[{rows[i]['doc']}] {rows[i]['text']}" for i in top)
    sources = list(dict.fromkeys(rows[i]["doc"] for i in top))

    if not await ollama_service.is_available():
        return {"answer": context[:600], "sources": sources}
    messages = [
        {"role": "system", "content": (
            "Answer the question using ONLY the provided context from the user's "
            "documents. If the answer isn't in the context, say you couldn't find "
            "it. Be concise and mention which document.")},
        {"role": "user", "content": f"Context:\n{context}\n\nQuestion: {question}"},
    ]
    answer = await ollama_service.chat(messages, temperature=0.2, max_tokens=350)
    return {"answer": answer, "sources": sources}
