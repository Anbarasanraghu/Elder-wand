"""Turn a meeting/call transcript into a summary + action items via the local LLM."""
from app.services.llm import ollama_service


async def summarize(transcript: str) -> dict:
    transcript = (transcript or "").strip()
    if not transcript:
        return {"summary": "", "action_items": []}
    if not await ollama_service.is_available():
        return {"summary": transcript[:400], "action_items": []}
    messages = [
        {"role": "system", "content": (
            "You summarise a business meeting/client call transcript for an IT "
            "agency owner. Reply with ONE JSON object only: "
            '{"summary":"<3-5 sentence summary>","action_items":["<task>", ...]}. '
            "Action items are concrete next steps/todos. Keep them short.")},
        {"role": "user", "content": transcript},
    ]
    data = await ollama_service.chat_json(messages, max_tokens=500)
    summary = (data.get("summary") or "").strip()
    actions = data.get("action_items")
    if not isinstance(actions, list):
        actions = []
    # Never return an empty summary when we actually have a transcript.
    if not summary:
        summary = transcript if len(transcript) <= 500 else transcript[:500] + "…"
    return {"summary": summary, "action_items": [str(a) for a in actions]}
