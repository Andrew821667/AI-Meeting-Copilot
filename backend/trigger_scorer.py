from __future__ import annotations

import re
from dataclasses import dataclass

from models import TranscriptSegment
from profile_loader import Profile


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
    def __init__(self, profile: Profile) -> None:
        self.profile = profile
        self.last_breakdown = ScoreBreakdown(keyword_score=0.0)

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
        self.last_breakdown = ScoreBreakdown(keyword_score=keyword_score)
        return self.last_breakdown.total
