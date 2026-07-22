"""Project tracker — the build phase after a lead is won.

Each project carries a JSON checklist of milestones. SQLite, stdlib only.
Path resolves to app/akeriyan_projects.db (same pattern as the other stores).
"""
import json
import os
import sqlite3
from datetime import datetime

_DB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "akeriyan_projects.db",
)

STATUSES = ["planning", "in_progress", "review", "delivered", "on_hold"]

_DEFAULT_MILESTONES = {
    "website": ["Discovery", "Design", "Development", "Review", "Launch"],
    "app": ["Discovery", "UI/UX", "Development", "Testing", "Release"],
    "automation": ["Scope", "Build", "Test", "Deploy"],
}

_COLS = ["id", "name", "company", "service", "status", "milestones",
         "deadline", "notes", "value", "created_at", "updated_at"]


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute(
        "CREATE TABLE IF NOT EXISTS projects ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "name TEXT, company TEXT, service TEXT, status TEXT DEFAULT 'planning', "
        "milestones TEXT DEFAULT '[]', deadline TEXT DEFAULT '', "
        "notes TEXT DEFAULT '', value REAL DEFAULT 0, "
        "created_at TEXT NOT NULL, updated_at TEXT NOT NULL)"
    )
    return c


def _row(r: sqlite3.Row) -> dict:
    d = {k: r[k] for k in _COLS}
    try:
        d["milestones"] = json.loads(d["milestones"] or "[]")
    except Exception:
        d["milestones"] = []
    return d


def add_project(data: dict) -> dict:
    now = datetime.now().isoformat()
    service = (data.get("service") or "").strip().lower()
    milestones = data.get("milestones")
    if not milestones:
        titles = _DEFAULT_MILESTONES.get(service.split(",")[0].strip(),
                                         ["Kickoff", "Build", "Review", "Deliver"])
        milestones = [{"title": t, "done": False} for t in titles]
    row = {
        "name": (data.get("name") or "").strip(),
        "company": (data.get("company") or "").strip(),
        "service": service,
        "status": (data.get("status") or "planning").strip().lower(),
        "milestones": json.dumps(milestones),
        "deadline": (data.get("deadline") or "").strip(),
        "notes": (data.get("notes") or "").strip(),
        "value": float(data.get("value") or 0),
    }
    with _conn() as c:
        cur = c.execute(
            "INSERT INTO projects(name,company,service,status,milestones,deadline,"
            "notes,value,created_at,updated_at) VALUES(:name,:company,:service,"
            ":status,:milestones,:deadline,:notes,:value,:created_at,:updated_at)",
            {**row, "created_at": now, "updated_at": now},
        )
        return _row(c.execute("SELECT * FROM projects WHERE id=?",
                              (cur.lastrowid,)).fetchone())


def list_projects() -> list[dict]:
    with _conn() as c:
        rows = c.execute("SELECT * FROM projects ORDER BY updated_at DESC").fetchall()
    return [_row(r) for r in rows]


def get_project(pid: int) -> dict | None:
    with _conn() as c:
        r = c.execute("SELECT * FROM projects WHERE id=?", (pid,)).fetchone()
    return _row(r) if r else None


def update_project(pid: int, data: dict) -> dict | None:
    fields, vals = [], []
    for k in ("name", "company", "service", "status", "deadline", "notes", "value"):
        if k in data and data[k] is not None:
            fields.append(f"{k}=?")
            vals.append(data[k])
    if "milestones" in data and data["milestones"] is not None:
        fields.append("milestones=?")
        vals.append(json.dumps(data["milestones"]))
    if not fields:
        return get_project(pid)
    fields.append("updated_at=?")
    vals.append(datetime.now().isoformat())
    vals.append(pid)
    with _conn() as c:
        c.execute(f"UPDATE projects SET {','.join(fields)} WHERE id=?", vals)
    return get_project(pid)


def delete_project(pid: int) -> bool:
    with _conn() as c:
        return c.execute("DELETE FROM projects WHERE id=?", (pid,)).rowcount > 0
