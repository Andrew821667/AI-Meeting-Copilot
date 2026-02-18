from __future__ import annotations

import time


class EmotionDetector:
    """Лёгкий эмоциональный буст по тексту.

    Интерфейс совместим с будущим Wav2Vec2-интегратором.
    """

    def __init__(
        self,
        *,
        enabled: bool = False,
        call_on_keyword_hit: bool = True,
        call_interval_sec: float = 5.0,
    ) -> None:
        self.enabled = enabled
        self.call_on_keyword_hit = call_on_keyword_hit
        self.call_interval_sec = call_interval_sec
        self.last_run = 0.0

    def should_run(self, keyword_score: float) -> bool:
        if not self.enabled:
            return False
        if self.call_on_keyword_hit and keyword_score < 0.3:
            return False
        if (time.time() - self.last_run) < self.call_interval_sec:
            return False
        return True

    def detect_from_text(self, text: str, keyword_score: float) -> tuple[str, float]:
        if not self.should_run(keyword_score):
            return ("neutral", 0.0)
        self.last_run = time.time()

        lowered = text.lower()
        tense_markers = [
            "срочно",
            "критично",
            "блокер",
            "проблема",
            "штраф",
            "риск",
            "неустойка",
            "ошибка",
            "упало",
        ]
        excitement_markers = [
            "отлично",
            "супер",
            "классно",
            "рад",
        ]

        punctuation_boost = 0.15 if "!" in text else 0.0
        if any(marker in lowered for marker in tense_markers):
            confidence = min(1.0, 0.65 + punctuation_boost)
            return ("tense", confidence)

        if any(marker in lowered for marker in excitement_markers):
            confidence = min(1.0, 0.55 + punctuation_boost)
            return ("positive", confidence)

        return ("neutral", 0.0)
