from __future__ import annotations

import re
from dataclasses import dataclass

from emotion_detector import EmotionDetector
from models import TranscriptSegment
from profile_loader import Profile
from semantic_detector import SemanticDetector


@dataclass
class ScoreBreakdown:
    keyword_score: float
    semantic_shift: float = 0.0
    emotion_boost: float = 0.0

    @property
    def total(self) -> float:
        # Stage 2 runs keyword-only by default. Without optional signals,
        # weighted sum would cap at 0.5 and never pass profile threshold.
        if self.semantic_shift == 0.0 and self.emotion_boost == 0.0:
            return min(1.0, self.keyword_score)

        return min(1.0, self.keyword_score * 0.5 + self.semantic_shift * 0.3 + self.emotion_boost * 0.2)


def normalize(text: str) -> str:
    t = text.lower().replace("ё", "е")
    t = re.sub(r"[^\w\s-]", " ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return t


class TriggerScorer:
    def __init__(
        self,
        profile: Profile,
        *,
        semantic_detector: SemanticDetector | None = None,
        emotion_detector: EmotionDetector | None = None,
    ) -> None:
        self.profile = profile
        self.semantic_detector = semantic_detector or SemanticDetector(enabled=profile.semantic_enabled)
        self.emotion_detector = emotion_detector or EmotionDetector(enabled=profile.emotion_enabled)
        self.last_breakdown = ScoreBreakdown(keyword_score=0.0)
        self.optional_signals_enabled = True

    def set_optional_signals_enabled(self, enabled: bool) -> None:
        self.optional_signals_enabled = enabled

    def compute(self, segment: TranscriptSegment) -> float:
        text = normalize(segment.text)

        suppressed: set[str] = set()
        for neg in self.profile.negative_rules:
            neg_term = normalize(neg.value)
            if re.search(rf"\b{re.escape(neg_term)}\b", text):
                suppressed.update(neg.suppress)

        keyword_score = 0.0
        for rule in self.profile.trigger_vocab:
            if rule.value in suppressed:
                continue

            terms = [normalize(rule.value)] + [normalize(a) for a in rule.aliases]
            matched = False
            for term in terms:
                if rule.type == "token":
                    matched = bool(re.search(rf"\b{re.escape(term)}\b", text))
                else:
                    matched = term in text
                if matched:
                    break

            if matched:
                keyword_score += rule.weight

        keyword_score = min(keyword_score, 1.0)
        semantic_shift = 0.0
        emotion_boost = 0.0
        if self.optional_signals_enabled:
            semantic_shift = self.semantic_detector.compute(segment.text)
            emotion_label, emotion_conf = self.emotion_detector.detect_from_text(segment.text, keyword_score)
            emotion_boost = emotion_conf if emotion_label != "neutral" else 0.0

        self.last_breakdown = ScoreBreakdown(
            keyword_score=keyword_score,
            semantic_shift=semantic_shift,
            emotion_boost=emotion_boost,
        )
        return self.last_breakdown.total
