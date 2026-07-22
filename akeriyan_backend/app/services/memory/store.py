"""Persistent long-term memory — facts AKERIYAN remembers about you forever.

Backed by a local SQLite file (Python stdlib, no dependency). Survives
restarts, unlike the short conversation memory in session.py.
"""
import os
import re
import sqlite3
from datetime import datetime

_DB_PATH = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), "akeriyan_memory.db")


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB_PATH)
    c.execute(
        "CREATE TABLE IF NOT EXISTS facts ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "text TEXT NOT NULL, "
        "created_at TEXT NOT NULL)"
    )
    return c


def remember(text: str) -> str:
    """Store a fact. Returns a short spoken confirmation."""
    text = (text or "").strip().rstrip(".")
    if not text:
        return "There was nothing to remember."
    with _conn() as c:
        # avoid exact duplicates
        existing = c.execute(
            "SELECT 1 FROM facts WHERE lower(text)=lower(?)", (text,)
        ).fetchone()
        if not existing:
            c.execute("INSERT INTO facts(text, created_at) VALUES(?, ?)",
                      (text, datetime.now().isoformat()))
    return f"Got it. I'll remember that {text}."


def all_facts() -> list[str]:
    with _conn() as c:
        rows = c.execute("SELECT text FROM facts ORDER BY id").fetchall()
    return [r[0] for r in rows]


def recall_spoken() -> str:
    facts = all_facts()
    if not facts:
        return "I don't have anything remembered about you yet. Say 'remember that...' to teach me."
    return "Here's what I know: " + ". ".join(facts) + "."


def forget(query: str | None) -> str:
    """Forget matching facts, or everything if query is 'everything'/empty-all."""
    q = (query or "").strip().lower()
    with _conn() as c:
        if q in ("", "everything", "all", "it all"):
            c.execute("DELETE FROM facts")
            return "Done. I've forgotten everything."
        cur = c.execute("SELECT id, text FROM facts")
        ids = [row[0] for row in cur.fetchall()
               if q in row[1].lower()]
        if not ids:
            return "I couldn't find anything like that to forget."
        c.executemany("DELETE FROM facts WHERE id=?", [(i,) for i in ids])
    return "Okay, I've forgotten that."


def facts_context() -> str:
    """A block injected into LLM prompts so the model knows you personally."""
    facts = all_facts()
    if not facts:
        return ""
    lines = "\n".join(f"- {f}" for f in facts)
    return f"\nThings you already know about the user:\n{lines}\n"


# ---- helpers for the 'remember' intent ------------------------------------
_REMEMBER_RE = re.compile(
    r'^\s*(?:please\s+)?(?:remember|note|keep in mind|don\'?t forget)'
    r'(?:\s+that)?\s+(.+)$', re.I)


def extract_fact(text: str) -> str | None:
    m = _REMEMBER_RE.match(text.strip())
    return m.group(1).strip() if m else None
