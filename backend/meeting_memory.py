from __future__ import annotations

from dataclasses import dataclass, field

from models import InsightCard, TranscriptSegment


@dataclass
class MeetingMemory:
    summary_bullets: list[str] = field(default_factory=list)
    decisions: list[str] = field(default_factory=list)
    risks: list[str] = field(default_factory=list)
    open_questions: list[str] = field(default_factory=list)
    action_items: list[str] = field(default_factory=list)
    last_updated: float = 0.0


class MeetingMemoryUpdater:
    """Adaptive meeting memory updates with event-driven triggers."""

    TIMER_INTERVAL_MIN = 10
    HIGH_THRESHOLD = 0.80

    def __init__(self) -> None:
        self.memory = MeetingMemory()
        self._last_update_ts = 0.0

    def should_update(self, semantic_shift: float, last_card_severity: str | None, elapsed_min: float) -> bool:
        return any(
            [
                semantic_shift > self.HIGH_THRESHOLD,
                last_card_severity == "alert",
                elapsed_min >= self.TIMER_INTERVAL_MIN,
            ]
        )

    def maybe_update(self, *, segment: TranscriptSegment, score: float, last_card_severity: str | None) -> bool:
        elapsed_min = max(0.0, segment.tsEnd - self._last_update_ts) / 60.0
        if not self.should_update(score, last_card_severity, elapsed_min):
            return False

        self._apply_segment(segment, score)
        self._last_update_ts = segment.tsEnd
        self.memory.last_updated = segment.tsEnd
        return True

    def update_on_meeting_end(self, transcript: list[TranscriptSegment], cards: list[InsightCard], ended_ts: float) -> dict:
        if transcript:
            tail = transcript[-5:]
            for seg in tail:
                self._apply_segment(seg, score=1.0)

        for card in cards[-5:]:
            if card.severity in {"warning", "alert"}:
                self._append_unique(self.memory.risks, card.insight)

        if transcript:
            self._append_unique(self.memory.summary_bullets, f"Реплик THEM: {len([x for x in transcript if x.speaker.startswith('THEM')])}")
        self._append_unique(self.memory.summary_bullets, f"Карточек показано: {len(cards)}")
        self.memory.last_updated = ended_ts

        return {
            "summary_bullets": self.memory.summary_bullets,
            "decisions": self.memory.decisions,
            "risks": self.memory.risks,
            "open_questions": self.memory.open_questions,
            "action_items": self.memory.action_items,
            "last_updated": self.memory.last_updated,
        }

    def _apply_segment(self, segment: TranscriptSegment, score: float) -> None:
        text = segment.text.strip()
        if not text:
            return

        if score >= self.HIGH_THRESHOLD:
            self._append_unique(self.memory.summary_bullets, text)

        lowered = text.lower()
        if any(k in lowered for k in ["согласовали", "решили", "подтвердили"]):
            self._append_unique(self.memory.decisions, text)
        if any(k in lowered for k in ["риск", "штраф", "неустойка", "ультиматум"]):
            self._append_unique(self.memory.risks, text)
        if "?" in text or any(k in lowered for k in ["уточнить", "вопрос"]):
            self._append_unique(self.memory.open_questions, text)
        if any(k in lowered for k in ["сделаем", "отправлю", "подготовим", "зафиксируем"]):
            self._append_unique(self.memory.action_items, text)

    def _append_unique(self, bucket: list[str], value: str) -> None:
        if value and value not in bucket:
            bucket.append(value)
