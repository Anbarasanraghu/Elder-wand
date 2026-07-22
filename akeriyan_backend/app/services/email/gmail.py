"""Gmail over IMAP/SMTP — free, no API key, just a Gmail App Password.

Reads recent inbox mail (without marking it read) and can send replies.
All blocking IMAP/SMTP work runs in a thread so it doesn't block the server.
"""
import asyncio
import email
import imaplib
import smtplib
from email.header import decode_header
from email.mime.text import MIMEText
from email.utils import parseaddr

from app.config import settings
from app.services.llm import ollama_service

_IMAP_HOST = "imap.gmail.com"
_SMTP_HOST = "smtp.gmail.com"
_SMTP_PORT = 587


def configured() -> bool:
    return bool(settings.gmail_user and settings.gmail_app_password)


def _decode(value: str | None) -> str:
    if not value:
        return ""
    out = ""
    for text, enc in decode_header(value):
        if isinstance(text, bytes):
            out += text.decode(enc or "utf-8", errors="ignore")
        else:
            out += text
    return out


def _snippet(msg: email.message.Message, limit: int = 220) -> str:
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            if part.get_content_type() == "text/plain" and \
                    "attachment" not in str(part.get("Content-Disposition")):
                try:
                    body = part.get_payload(decode=True).decode(
                        part.get_content_charset() or "utf-8", errors="ignore")
                    break
                except Exception:
                    continue
    else:
        try:
            body = msg.get_payload(decode=True).decode(
                msg.get_content_charset() or "utf-8", errors="ignore")
        except Exception:
            body = ""
    body = " ".join(body.split())
    return body[:limit]


def _fetch(limit: int, unread_only: bool) -> list[dict]:
    m = imaplib.IMAP4_SSL(_IMAP_HOST)
    try:
        m.login(settings.gmail_user, settings.gmail_app_password)
        m.select("INBOX")
        typ, data = m.search(None, "UNSEEN" if unread_only else "ALL")
        ids = data[0].split()
        ids = ids[-limit:] if ids else []
        out = []
        for i in reversed(ids):
            # BODY.PEEK does not set the \Seen flag (keeps it unread).
            typ, msg_data = m.fetch(i, "(BODY.PEEK[])")
            if not msg_data or not msg_data[0]:
                continue
            msg = email.message_from_bytes(msg_data[0][1])
            name, addr = parseaddr(_decode(msg.get("From")))
            out.append({
                "from": name or addr,
                "from_email": addr,
                "subject": _decode(msg.get("Subject")) or "(no subject)",
                "date": _decode(msg.get("Date")),
                "snippet": _snippet(msg),
            })
        return out
    finally:
        try:
            m.logout()
        except Exception:
            pass


async def inbox(limit: int = 6, unread_only: bool = True) -> dict:
    if not configured():
        return {"ok": False, "emails": [],
                "error": "Gmail isn't set up. Add a Gmail App Password in config."}
    try:
        emails = await asyncio.to_thread(_fetch, limit, unread_only)
        return {"ok": True, "emails": emails}
    except Exception as e:  # noqa: BLE001
        print(f"[AKERIYAN] Gmail fetch error: {e}")
        return {"ok": False, "emails": [], "error": "Couldn't reach Gmail."}


def _send(to: str, subject: str, body: str) -> None:
    msg = MIMEText(body, "plain", "utf-8")
    msg["From"] = settings.gmail_user
    msg["To"] = to
    msg["Subject"] = subject
    with smtplib.SMTP(_SMTP_HOST, _SMTP_PORT) as s:
        s.starttls()
        s.login(settings.gmail_user, settings.gmail_app_password)
        s.send_message(msg)


async def send(to: str, subject: str, body: str) -> dict:
    if not configured():
        return {"ok": False, "error": "Gmail isn't set up."}
    try:
        await asyncio.to_thread(_send, to, subject, body)
        return {"ok": True}
    except Exception as e:  # noqa: BLE001
        print(f"[AKERIYAN] Gmail send error: {e}")
        return {"ok": False, "error": "Couldn't send the email."}


async def summarize_emails(emails: list[dict]) -> str:
    """Spoken summary of an already-fetched list of emails (no extra IMAP call)."""
    if not emails:
        return "You have no new emails."
    if not await ollama_service.is_available():
        lines = "; ".join(f"{e['from']}: {e['subject']}" for e in emails[:5])
        return f"You have {len(emails)} new emails. {lines}."
    listing = "\n".join(
        f"- From {e['from']}: {e['subject']} — {e['snippet']}" for e in emails)
    messages = [
        {"role": "system", "content": (
            "Summarise the user's new emails in 2-4 spoken sentences: who wrote "
            "and what they want. Group similar ones. Be concise, natural.")},
        {"role": "user", "content": listing},
    ]
    return await ollama_service.chat(messages, temperature=0.4, max_tokens=250)


async def spoken_summary(limit: int = 6) -> str:
    """Fetch the newest unread emails and speak a short summary."""
    data = await inbox(limit)
    if not data["ok"]:
        return data.get("error", "I couldn't check your email.")
    return await summarize_emails(data["emails"])
