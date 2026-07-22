"""CRM / lead-and-client tracker for the IT agency — persistent SQLite store.

Pipeline: new -> contacted -> proposal -> negotiation -> won / lost.
Free, offline, no dependency (Python stdlib sqlite3). One row per lead/client.
"""
import os
import sqlite3
from datetime import datetime

_DB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "akeriyan_crm.db",
)

STAGES = ["new", "contacted", "proposal", "negotiation", "won", "lost"]
SCORES = ["hot", "warm", "cold"]

_COLUMNS = [
    "id", "name", "company", "email", "phone", "source", "service",
    "value", "stage", "score", "notes", "next_followup",
    "created_at", "updated_at",
]


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute(
        "CREATE TABLE IF NOT EXISTS leads ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "name TEXT, company TEXT, email TEXT, phone TEXT, "
        "source TEXT, service TEXT, value REAL DEFAULT 0, "
        "stage TEXT DEFAULT 'new', score TEXT DEFAULT 'warm', "
        "notes TEXT, next_followup TEXT, "
        "created_at TEXT NOT NULL, updated_at TEXT NOT NULL)"
    )
    return c


def _row(r: sqlite3.Row) -> dict:
    return {k: r[k] for k in _COLUMNS}


def add_lead(data: dict) -> dict:
    now = datetime.now().isoformat()
    fields = {
        "name": (data.get("name") or "").strip(),
        "company": (data.get("company") or "").strip(),
        "email": (data.get("email") or "").strip(),
        "phone": (data.get("phone") or "").strip(),
        "source": (data.get("source") or "").strip(),
        "service": (data.get("service") or "").strip(),
        "value": float(data.get("value") or 0),
        "stage": (data.get("stage") or "new").strip().lower(),
        "score": (data.get("score") or "warm").strip().lower(),
        "notes": (data.get("notes") or "").strip(),
        "next_followup": (data.get("next_followup") or "").strip(),
    }
    if fields["stage"] not in STAGES:
        fields["stage"] = "new"
    if fields["score"] not in SCORES:
        fields["score"] = "warm"
    with _conn() as c:
        cur = c.execute(
            "INSERT INTO leads(name,company,email,phone,source,service,value,"
            "stage,score,notes,next_followup,created_at,updated_at) "
            "VALUES(:name,:company,:email,:phone,:source,:service,:value,"
            ":stage,:score,:notes,:next_followup,:created_at,:updated_at)",
            {**fields, "created_at": now, "updated_at": now},
        )
        rid = cur.lastrowid
        return _row(c.execute("SELECT * FROM leads WHERE id=?", (rid,)).fetchone())


def list_leads(stage: str | None = None) -> list[dict]:
    with _conn() as c:
        if stage and stage in STAGES:
            rows = c.execute(
                "SELECT * FROM leads WHERE stage=? ORDER BY updated_at DESC",
                (stage,),
            ).fetchall()
        else:
            rows = c.execute(
                "SELECT * FROM leads ORDER BY updated_at DESC"
            ).fetchall()
    return [_row(r) for r in rows]


def get_lead(lead_id: int) -> dict | None:
    with _conn() as c:
        r = c.execute("SELECT * FROM leads WHERE id=?", (lead_id,)).fetchone()
    return _row(r) if r else None


def update_lead(lead_id: int, data: dict) -> dict | None:
    allowed = [k for k in _COLUMNS if k not in ("id", "created_at")]
    sets, vals = [], []
    for k in allowed:
        if k in data and data[k] is not None:
            sets.append(f"{k}=?")
            vals.append(data[k])
    if not sets:
        return get_lead(lead_id)
    sets.append("updated_at=?")
    vals.append(datetime.now().isoformat())
    vals.append(lead_id)
    with _conn() as c:
        c.execute(f"UPDATE leads SET {','.join(sets)} WHERE id=?", vals)
    return get_lead(lead_id)


def delete_lead(lead_id: int) -> bool:
    with _conn() as c:
        cur = c.execute("DELETE FROM leads WHERE id=?", (lead_id,))
        return cur.rowcount > 0


def analytics() -> dict:
    leads = list_leads()
    total = len(leads)
    by_stage = {s: 0 for s in STAGES}
    by_source: dict[str, int] = {}
    pipeline_value = 0.0   # value of open (not won/lost) leads
    won_revenue = 0.0
    for l in leads:
        by_stage[l["stage"]] = by_stage.get(l["stage"], 0) + 1
        src = l["source"] or "unknown"
        by_source[src] = by_source.get(src, 0) + 1
        if l["stage"] == "won":
            won_revenue += l["value"] or 0
        elif l["stage"] != "lost":
            pipeline_value += l["value"] or 0
    won = by_stage.get("won", 0)
    lost = by_stage.get("lost", 0)
    closed = won + lost
    conversion = round((won / closed) * 100) if closed else 0
    now = datetime.now().isoformat()
    overdue = [
        {"id": l["id"], "name": l["name"], "company": l["company"],
         "next_followup": l["next_followup"]}
        for l in leads
        if l["next_followup"] and l["next_followup"] < now
        and l["stage"] not in ("won", "lost")
    ]
    return {
        "total": total,
        "by_stage": by_stage,
        "by_source": by_source,
        "pipeline_value": round(pipeline_value),
        "won_revenue": round(won_revenue),
        "conversion_pct": conversion,
        "overdue_followups": overdue,
    }
