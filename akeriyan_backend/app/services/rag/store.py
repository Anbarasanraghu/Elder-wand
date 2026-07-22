"""Vector store for Ask-your-documents (RAG). SQLite, embeddings as JSON.

Small-scale (personal): all chunk vectors are loaded into memory for cosine
search — fine for hundreds/thousands of chunks.
"""
import json
import os
import sqlite3
from datetime import datetime

_DB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "akeriyan_docs.db",
)


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute(
        "CREATE TABLE IF NOT EXISTS chunks ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "doc TEXT NOT NULL, text TEXT NOT NULL, "
        "embedding TEXT NOT NULL, created_at TEXT NOT NULL)"
    )
    return c


def add_chunk(doc: str, text: str, embedding: list[float]) -> None:
    with _conn() as c:
        c.execute(
            "INSERT INTO chunks(doc,text,embedding,created_at) VALUES(?,?,?,?)",
            (doc, text, json.dumps(embedding), datetime.now().isoformat()),
        )


def all_chunks() -> list[dict]:
    with _conn() as c:
        rows = c.execute("SELECT doc,text,embedding FROM chunks").fetchall()
    return [{"doc": r["doc"], "text": r["text"],
             "embedding": json.loads(r["embedding"])} for r in rows]


def list_docs() -> list[dict]:
    with _conn() as c:
        rows = c.execute(
            "SELECT doc, COUNT(*) n, MIN(created_at) at FROM chunks "
            "GROUP BY doc ORDER BY at DESC"
        ).fetchall()
    return [{"doc": r["doc"], "chunks": r["n"], "at": r["at"]} for r in rows]


def delete_doc(doc: str) -> int:
    with _conn() as c:
        return c.execute("DELETE FROM chunks WHERE doc=?", (doc,)).rowcount
