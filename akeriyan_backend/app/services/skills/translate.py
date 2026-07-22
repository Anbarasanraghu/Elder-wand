"""Translation via the free local LLM — no key, works offline."""
from app.services.nlu import llm_nlu
from app.services.llm import ollama_service


async def to_english(text: str) -> str:
    """Raw English translation of `text` (for internal bilingual processing)."""
    if not text or not await ollama_service.is_available():
        return text
    try:
        r = await ollama_service.chat(
            [{"role": "user", "content":
              "Translate this to English. Reply with ONLY the translation, "
              f"nothing else:\n\n{text}"}], temperature=0.1, max_tokens=200)
        return r.strip() or text
    except Exception:
        return text


async def to_language(text: str, language: str) -> str:
    """Raw translation of `text` into `language` (e.g. 'Tamil')."""
    if not text or not await ollama_service.is_available():
        return text
    try:
        r = await ollama_service.chat(
            [{"role": "user", "content":
              f"Translate this to {language}. Reply with ONLY the translation "
              f"in {language} script, no notes or transliteration:\n\n{text}"}],
            temperature=0.1, max_tokens=300)
        return r.strip() or text
    except Exception:
        return text


async def translate(text: str, target_language: str | None) -> str:
    target = (target_language or "the target language").strip()
    if not text:
        return "What would you like me to translate?"
    if not await ollama_service.is_available():
        return "Translation needs my AI brain. Please start Ollama on the PC."
    prompt = (f'Translate the following into {target}. '
              f'Reply with ONLY the translation, nothing else:\n\n{text}')
    try:
        result = await ollama_service.chat(
            [{"role": "user", "content": prompt}], temperature=0.2)
        return f"In {target}, that's: {result}"
    except Exception:
        return "I couldn't translate that right now."
