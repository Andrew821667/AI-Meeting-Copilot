from __future__ import annotations

import asyncio
import time
import uuid
from collections import deque

from llm_client import RealtimeLLMClient
from models import InsightCard, MicEvent, RawBufferEntry, TranscriptSegment
from profile_loader import Profile
from raw_buffer import RawBuffer
from trigger_scorer import TriggerScorer


class TriggerOrchestrator:
    def __init__(self, profile: Profile) -> None:
        self.profile = profile
        self.raw_buffer = RawBuffer(max_duration_sec=300)
        self.scorer = TriggerScorer(profile)
        self.llm = RealtimeLLMClient(timeout_sec=3.0)

        self.mic_speaking = False
        self.last_speech_end_ts = 0.0
        self.last_trigger_ts = 0.0
        self.recent_card_ts: deque[float] = deque()
        self.recent_utterances: deque[str] = deque(maxlen=50)
        self.pending_queue: deque[InsightCard] = deque(maxlen=20)

    async def on_mic_event(self, event: MicEvent) -> list[InsightCard]:
        cards: list[InsightCard] = []

        if event.eventType == "speech_start":
            self.mic_speaking = True
            return cards

        if event.eventType == "speech_end":
            self.mic_speaking = False
            self.last_speech_end_ts = event.timestamp
            if self.pending_queue:
                cards.append(self.pending_queue.popleft())

        return cards

    async def on_transcript_segment(self, segment: TranscriptSegment) -> list[InsightCard]:
        cards: list[InsightCard] = []

        if not segment.isFinal:
            return cards

        self.raw_buffer.append(
            RawBufferEntry(
                speaker=segment.speaker,
                text=segment.text,
                ts_start=segment.tsStart,
                ts_end=segment.tsEnd,
            )
        )

        score = self.scorer.compute(segment)
        if not self._should_trigger(score=score, segment=segment):
            return cards

        context = self.raw_buffer.recent_text(max_items=20)
        trigger_reason = self._build_trigger_reason(segment=segment, score=score)
        card = await self.llm.build_card(
            scenario=self.profile.id,
            speaker=segment.speaker,
            trigger_reason=trigger_reason,
            context=context,
        )

        now = time.monotonic()
        self.last_trigger_ts = now
        self.recent_utterances.append(segment.utteranceId)
        self.recent_card_ts.append(now)
        self._trim_card_window(now)

        if self.mic_speaking:
            self._enqueue_pending(card)
            return cards

        pause_duration = max(0.0, segment.tsEnd - self.last_speech_end_ts)
        if pause_duration >= self.profile.min_pause_sec:
            cards.append(card)
        else:
            self._enqueue_pending(card)

        return cards

    async def on_manual_capture(self) -> list[InsightCard]:
        recent = self.raw_buffer.last_seconds(30)
        text = "\n".join(f"{e.speaker}: {e.text}" for e in recent)

        card = InsightCard(
            id=str(uuid.uuid4()),
            scenario=self.profile.id,
            card_mode="reply_suggestions",
            trigger_reason="Ручной захват момента",
            insight=f"Ключевой контекст (30с): {text[:120] if text else 'контекст пуст'}",
            reply_cautious="Уточни формулировку и подтверди её письменно.",
            reply_confident="Фиксируй сейчас: это критичный момент переговоров.",
            severity="info",
            timestamp=time.monotonic(),
            speaker="THEM",
            is_fallback=False,
        )

        if self.mic_speaking:
            self._enqueue_pending(card)
            return []
        return [card]

    def _should_trigger(self, score: float, segment: TranscriptSegment) -> bool:
        if score < self.profile.threshold:
            return False

        if self.raw_buffer.duration_minutes() < self.profile.min_context_min:
            return False

        if segment.utteranceId in self.recent_utterances:
            return False

        now = time.monotonic()
        if (now - self.last_trigger_ts) < self.profile.cooldown_sec:
            return False

        self._trim_card_window(now)
        if len(self.recent_card_ts) >= self.profile.max_cards_per_10min:
            return False

        return True

    def _trim_card_window(self, now: float) -> None:
        window_start = now - 600
        while self.recent_card_ts and self.recent_card_ts[0] < window_start:
            self.recent_card_ts.popleft()

    def _build_trigger_reason(self, segment: TranscriptSegment, score: float) -> str:
        snippet = segment.text.strip().replace("\n", " ")[:64]
        return f"обнаружен важный момент (score={score:.2f}): {snippet}"

    def _enqueue_pending(self, card: InsightCard) -> None:
        if len(self.pending_queue) >= self.pending_queue.maxlen:
            self.pending_queue.clear()
            summary = InsightCard(
                id=str(uuid.uuid4()),
                scenario=self.profile.id,
                card_mode="reply_suggestions",
                trigger_reason="очередь карточек переполнена",
                insight="20 важных моментов пока вы говорили.",
                reply_cautious="Сделайте короткую паузу, чтобы показать сводку.",
                reply_confident="Остановимся на 10 секунд и разберём сводку моментов.",
                severity="warning",
                timestamp=time.monotonic(),
                speaker="THEM",
                is_fallback=False,
            )
            self.pending_queue.append(summary)
            return

        self.pending_queue.append(card)
