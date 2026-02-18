from __future__ import annotations

import time


class SemanticDetector:
    """Лёгкий semantic-shift детектор без тяжёлых моделей.

    В production может быть заменён на MiniLM-эмбеддинги без смены интерфейса.
    """

    MIN_TOKENS = 5
    MAX_CALLS_PER_SEC = 2.0
    CALL_EVERY_N_REPLIES = 5

    def __init__(self, enabled: bool = False) -> None:
        self.enabled = enabled
        self.last_call_time = 0.0
        self.reply_counter = 0
        self._previous_tokens: set[str] | None = None

    def _is_informative(self, text: str) -> bool:
        return len(text.strip().split()) >= self.MIN_TOKENS

    def _should_compute(self, text: str) -> bool:
        if not self.enabled:
            return False

        self.reply_counter += 1
        if self.reply_counter % self.CALL_EVERY_N_REPLIES != 0:
            return False

        now = time.time()
        if (now - self.last_call_time) < (1.0 / self.MAX_CALLS_PER_SEC):
            return False

        if not self._is_informative(text):
            return False

        self.last_call_time = now
        return True

    def compute(self, text: str) -> float:
        if not self._should_compute(text):
            return 0.0

        current_tokens = {t for t in text.lower().split() if t}
        if not current_tokens:
            return 0.0

        if self._previous_tokens is None:
            self._previous_tokens = current_tokens
            return 0.0

        intersection = len(current_tokens & self._previous_tokens)
        union = len(current_tokens | self._previous_tokens)
        self._previous_tokens = current_tokens
        if union == 0:
            return 0.0

        jaccard = intersection / union
        return min(1.0, max(0.0, 1.0 - jaccard))
