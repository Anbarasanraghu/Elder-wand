"""Short conversation memory so follow-ups work.

'Remind me at 8' -> 'make it 9 instead' -> the model still knows the topic.
In-memory only (clears on restart); good enough for a personal assistant.
"""
from collections import deque

_MAX_TURNS = 8  # remember the last 8 user/assistant exchanges


class _History:
    def __init__(self) -> None:
        self._turns: deque[dict] = deque(maxlen=_MAX_TURNS * 2)

    def add_user(self, text: str) -> None:
        self._turns.append({"role": "user", "content": text})

    def add_assistant(self, text: str) -> None:
        if text:
            self._turns.append({"role": "assistant", "content": text})

    def as_messages(self) -> list[dict]:
        return list(self._turns)

    def clear(self) -> None:
        self._turns.clear()


# Single-user assistant -> one shared history is fine.
history = _History()
