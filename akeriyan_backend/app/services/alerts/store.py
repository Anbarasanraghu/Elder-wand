"""Proactive alerts — price/RSI rules + a delivery queue the phone polls.

SQLite, stdlib only. Rules are evaluated by checker.py on a background loop;
when one fires, a message is enqueued in `pending` and the app picks it up via
GET /v1/alerts/pending and shows a local notification.
"""
import os
import sqlite3
from datetime import datetime

_DB_PATH = os.path.join(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))),
    "akeriyan_alerts.db",
)

_RULE_COLS = ["id", "symbol", "kind", "op", "threshold", "active",
              "cooldown_until", "note", "created_at"]


def _conn() -> sqlite3.Connection:
    c = sqlite3.connect(_DB_PATH)
    c.row_factory = sqlite3.Row
    c.execute(
        "CREATE TABLE IF NOT EXISTS rules ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "symbol TEXT NOT NULL, kind TEXT DEFAULT 'price', "
        "op TEXT DEFAULT 'above', threshold REAL NOT NULL, "
        "active INTEGER DEFAULT 1, cooldown_until TEXT DEFAULT '', "
        "note TEXT DEFAULT '', created_at TEXT NOT NULL)"
    )
    c.execute(
        "CREATE TABLE IF NOT EXISTS pending ("
        "id INTEGER PRIMARY KEY AUTOINCREMENT, "
        "title TEXT NOT NULL, body TEXT NOT NULL, "
        "created_at TEXT NOT NULL, delivered INTEGER DEFAULT 0)"
    )
    c.execute("CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)")
    return c


# ---- rules ----
def add_rule(d: dict) -> dict:
    now = datetime.now().isoformat()
    row = {
        "symbol": (d.get("symbol") or "").strip().lower(),
        "kind": (d.get("kind") or "price").strip().lower(),
        "op": (d.get("op") or "above").strip().lower(),
        "threshold": float(d.get("threshold") or 0),
        "note": (d.get("note") or "").strip(),
    }
    with _conn() as c:
        cur = c.execute(
            "INSERT INTO rules(symbol,kind,op,threshold,active,cooldown_until,"
            "note,created_at) VALUES(:symbol,:kind,:op,:threshold,1,'',:note,:created_at)",
            {**row, "created_at": now},
        )
        r = c.execute("SELECT * FROM rules WHERE id=?", (cur.lastrowid,)).fetchone()
        return {k: r[k] for k in _RULE_COLS}


def list_rules() -> list[dict]:
    with _conn() as c:
        rows = c.execute("SELECT * FROM rules ORDER BY id DESC").fetchall()
    return [{k: r[k] for k in _RULE_COLS} for r in rows]


def active_rules() -> list[dict]:
    with _conn() as c:
        rows = c.execute("SELECT * FROM rules WHERE active=1").fetchall()
    return [{k: r[k] for k in _RULE_COLS} for r in rows]


def delete_rule(rule_id: int) -> bool:
    with _conn() as c:
        return c.execute("DELETE FROM rules WHERE id=?", (rule_id,)).rowcount > 0


def set_cooldown(rule_id: int, until_iso: str) -> None:
    with _conn() as c:
        c.execute("UPDATE rules SET cooldown_until=? WHERE id=?", (until_iso, rule_id))


# ---- pending delivery queue ----
def enqueue(title: str, body: str) -> None:
    with _conn() as c:
        c.execute(
            "INSERT INTO pending(title,body,created_at,delivered) VALUES(?,?,?,0)",
            (title, body, datetime.now().isoformat()),
        )


def take_pending() -> list[dict]:
    """Return undelivered notifications and mark them delivered."""
    with _conn() as c:
        rows = c.execute(
            "SELECT id,title,body,created_at FROM pending WHERE delivered=0 "
            "ORDER BY id"
        ).fetchall()
        ids = [r["id"] for r in rows]
        if ids:
            c.execute(
                f"UPDATE pending SET delivered=1 WHERE id IN ({','.join('?' * len(ids))})",
                ids,
            )
    return [{"title": r["title"], "body": r["body"], "at": r["created_at"]}
            for r in rows]


# ---- settings ----
def get_setting(key: str, default: str = "") -> str:
    with _conn() as c:
        r = c.execute("SELECT value FROM settings WHERE key=?", (key,)).fetchone()
    return r["value"] if r else default


def set_setting(key: str, value: str) -> None:
    with _conn() as c:
        c.execute(
            "INSERT INTO settings(key,value) VALUES(?,?) "
            "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
            (key, value),
        )
