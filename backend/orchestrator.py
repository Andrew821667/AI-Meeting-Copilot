from __future__ import annotations

import asyncio
import time
import uuid
from collections import deque

from diarization_gate import DiarizationGate
from llm_client import RealtimeLLMClient
from meeting_memory import MeetingMemoryUpdater
from models import AudioLevelEvent, InsightCard, MicEvent, RawBufferEntry, SystemStateEvent, TranscriptSegment
from profile_loader import Profile
from raw_buffer import RawBuffer
from telemetry import TelemetryCollector
from trigger_scorer import TriggerScorer, normalize


class TriggerOrchestrator:
    MAIN_AGENT_PROFILE = (
        "Оркестратор",
        "Главная карточка-подсказка. Дай короткий практический совет и два варианта ответа "
        "(осторожный/уверенный) по текущему контексту.",
    )
    PSYCHOLOGIST_AGENT_PROFILE = (
        "Психолог",
        "Кратко проанализируй психологию и давление собеседника: эмоциональный фон, скрытый риск, "
        "и один практический совет, как ответить спокойнее.",
    )
    DIRECT_FORCE_AGENT_PROFILE = (
        "Принудительный ответ",
        "Прямой поток помощи (вне оркестратора): ответь по сути на текущий вопрос/реплику. "
        "Формат: 1-2 фразы, затем осторожный и уверенный варианты.",
    )

    def __init__(self, profile: Profile, telemetry: TelemetryCollector | None = None) -> None:
        self.profile = profile
        self.raw_buffer = RawBuffer(max_duration_sec=300)
        self.scorer = TriggerScorer(profile)
        self.llm = RealtimeLLMClient.from_env(timeout_sec=15.0)
        self.telemetry = telemetry or TelemetryCollector()

        self.mic_speaking = False
        self.paused = False
        self.last_speech_end_ts = 0.0
        self.last_trigger_ts = -1_000_000_000.0
        self.recent_card_ts: deque[float] = deque()
        self.recent_utterances: deque[str] = deque(maxlen=50)
        self.pending_queue: deque[InsightCard] = deque(maxlen=20)

        self.transcript_history: list[TranscriptSegment] = []
        self.last_card_severity: str | None = None
        self.memory_updater = MeetingMemoryUpdater()
        self.diarization_gate = DiarizationGate()
        self.excluded_phrases: set[str] = set()
        self.degraded_mode = False
        self.force_answer_mode = profile.force_answer_mode
        self.force_answer_seen_utterances: deque[str] = deque(maxlen=200)
        self.last_force_answer_ts = -1_000_000_000.0
        self.force_answer_min_interval_sec = 1.5
        self.direct_force_seen_utterances: deque[str] = deque(maxlen=300)
        self.last_direct_force_ts = -1_000_000_000.0
        self.direct_force_min_interval_sec = 1.1
        self.last_direct_force_text: str = ""

    def set_paused(self, value: bool) -> None:
        self.paused = value

    def update_profile(self, profile: Profile) -> None:
        self.profile = profile
        self.scorer = TriggerScorer(profile)
        self.force_answer_mode = profile.force_answer_mode

    def set_excluded_phrases(self, phrases: set[str]) -> None:
        self.excluded_phrases = set(phrases)

    def add_excluded_phrase(self, phrase: str) -> str | None:
        normalized = normalize(phrase)
        if len(normalized) < 3:
            return None
        self.excluded_phrases.add(normalized)
        return normalized

    def meeting_memory_snapshot(self, ended_ts: float, cards: list[InsightCard]) -> dict:
        return self.memory_updater.update_on_meeting_end(self.transcript_history, cards, ended_ts)

    async def on_force_mode_activated(self) -> list[InsightCard]:
        if self.paused:
            return []

        source_ts_end = time.monotonic()
        context = self.raw_buffer.recent_text(max_items=20)
        if not context:
            context = "Контекст пока пуст. Ждём первую содержательную реплику."

        orchestrator_cards = await self._generate_cards_for_profiles(
            profiles=[self.MAIN_AGENT_PROFILE, self.PSYCHOLOGIST_AGENT_PROFILE],
            speaker="THEM",
            trigger_reason="поток оркестратора активирован",
            context=context,
            source_ts_end=source_ts_end,
            force_mode=True,
        )
        direct_cards = await self._generate_cards_for_profiles(
            profiles=[self.DIRECT_FORCE_AGENT_PROFILE],
            speaker="THEM",
            trigger_reason="прямой LLM-поток активирован",
            context=context,
            source_ts_end=source_ts_end,
            force_mode=True,
        )
        cards = [*orchestrator_cards, *direct_cards]
        for card in cards:
            self.telemetry.on_card_shown(card, shown_ts=source_ts_end)
        return cards

    async def on_mic_event(self, event: MicEvent) -> list[InsightCard]:
        if self.paused:
            return []

        cards: list[InsightCard] = []

        if event.eventType == "speech_start":
            self.mic_speaking = True
            return cards

        if event.eventType == "speech_end":
            self.mic_speaking = False
            self.last_speech_end_ts = event.timestamp
            while self.pending_queue and len(cards) < 3:
                shown = self.pending_queue.popleft()
                self.telemetry.on_card_shown(shown, shown_ts=event.timestamp)
                cards.append(shown)

            if not cards and self.force_answer_mode and self._should_emit_force_cards_on_mic_end():
                context = self.raw_buffer.recent_text(max_items=20)
                if not context:
                    context = "Контекст ограничен: последняя реплика пользователя завершена."
                generated = await self._generate_cards_for_profiles(
                    profiles=[self.MAIN_AGENT_PROFILE, self.PSYCHOLOGIST_AGENT_PROFILE],
                    speaker="ME",
                    trigger_reason="поток оркестратора: завершена реплика пользователя",
                    context=context,
                    source_ts_end=event.timestamp,
                    force_mode=True,
                )
                if generated:
                    now = time.monotonic()
                    self.last_force_answer_ts = now
                    self.last_card_severity = self._max_severity(generated)
                    self.recent_card_ts.append(now)
                    self._trim_card_window(now)
                    for card in generated:
                        self.telemetry.on_card_shown(card, shown_ts=event.timestamp)
                    cards.extend(generated)

        return cards

    async def on_audio_level(self, event: AudioLevelEvent) -> None:
        if self.paused:
            return
        self.telemetry.on_audio_level(event)

    async def on_system_state(self, event: SystemStateEvent) -> None:
        self.telemetry.on_system_state(event)
        should_degrade = event.thermalState in {"serious", "critical"} or event.batteryLevel < 0.2
        if should_degrade != self.degraded_mode:
            self.degraded_mode = should_degrade
            self.scorer.set_optional_signals_enabled(not should_degrade)

    async def on_transcript_segment(self, segment: TranscriptSegment) -> list[InsightCard]:
        cards: list[InsightCard] = []

        if self.paused:
            return cards

        if self.force_answer_mode and self._should_force_answer(segment):
            # Сохраняем сегмент в буферы ДО генерации — иначе контекст для LLM деградирует.
            # Partial-сегменты не добавляем в history (final перезапишет), но в raw_buffer — да.
            if segment.isFinal:
                self.transcript_history.append(segment)
            self.raw_buffer.append(
                RawBufferEntry(
                    speaker=segment.speaker,
                    text=segment.text,
                    ts_start=segment.tsStart,
                    ts_end=segment.tsEnd,
                )
            )

            context = self._build_force_context(segment)
            trigger_reason = self._build_force_answer_reason(segment)
            generated = await self._generate_cards_for_profiles(
                profiles=[self.MAIN_AGENT_PROFILE, self.PSYCHOLOGIST_AGENT_PROFILE],
                speaker=segment.speaker,
                trigger_reason=trigger_reason,
                context=context,
                source_ts_end=segment.tsEnd,
                force_mode=True,
            )
            if generated:
                now = time.monotonic()
                self.last_force_answer_ts = now
                self.force_answer_seen_utterances.append(segment.utteranceId)
                self.last_card_severity = self._max_severity(generated)
                self.recent_utterances.append(segment.utteranceId)
                self.recent_card_ts.append(now)
                self._trim_card_window(now)

                if self.mic_speaking:
                    for card in generated:
                        self._enqueue_pending(card)
                    return cards

                for card in generated:
                    self.telemetry.on_card_shown(card, shown_ts=segment.tsEnd)
                cards.extend(generated)
                return cards

        if not segment.isFinal:
            self.telemetry.asr_partial_latency_ms.append(400)
            return cards

        self.telemetry.asr_final_latency_ms.append(800)

        resolved_speaker = self.diarization_gate.resolve_speaker(segment)
        if resolved_speaker != segment.speaker:
            segment = TranscriptSegment(
                schemaVersion=segment.schemaVersion,
                seq=segment.seq,
                utteranceId=segment.utteranceId,
                isFinal=segment.isFinal,
                speaker=resolved_speaker,
                text=segment.text,
                tsStart=segment.tsStart,
                tsEnd=segment.tsEnd,
                speakerConfidence=segment.speakerConfidence,
            )

        self.telemetry.diarization_disabled_seconds = self.diarization_gate.disabled_seconds_remaining()

        self.transcript_history.append(segment)
        self.raw_buffer.append(
            RawBufferEntry(
                speaker=segment.speaker,
                text=segment.text,
                ts_start=segment.tsStart,
                ts_end=segment.tsEnd,
            )
        )

        score = self.scorer.compute(segment)
        self.memory_updater.maybe_update(segment=segment, score=score, last_card_severity=self.last_card_severity)

        if not self._should_trigger(score=score, segment=segment):
            return cards

        context = self.raw_buffer.recent_text(max_items=20)
        trigger_reason = self._build_trigger_reason(segment=segment, score=score)
        generated = await self._generate_cards_for_profiles(
            profiles=[self.MAIN_AGENT_PROFILE],
            speaker=segment.speaker,
            trigger_reason=trigger_reason,
            context=context,
            source_ts_end=segment.tsEnd,
            force_mode=False,
        )
        if not generated:
            return cards
        self.last_card_severity = self._max_severity(generated)

        now = time.monotonic()
        self.last_trigger_ts = now
        self.recent_utterances.append(segment.utteranceId)
        self.recent_card_ts.append(now)
        self._trim_card_window(now)

        if self.mic_speaking:
            for card in generated:
                self._enqueue_pending(card)
            return cards

        pause_duration = max(0.0, segment.tsEnd - self.last_speech_end_ts)
        if pause_duration >= self.profile.min_pause_sec:
            for card in generated:
                self.telemetry.on_card_shown(card, shown_ts=segment.tsEnd)
            cards.extend(generated)
        else:
            for card in generated:
                self._enqueue_pending(card)

        return cards

    async def on_manual_capture(self) -> list[InsightCard]:
        if self.paused:
            return []

        recent = self.raw_buffer.last_seconds(30)
        text = "\n".join(f"{e.speaker}: {e.text}" for e in recent)

        card = InsightCard(
            id=self._slot_card_id("Оркестратор"),
            scenario=self.profile.id,
            card_mode=self.profile.card_mode,
            trigger_reason="Ручной захват момента",
            insight=f"Ключевой контекст (30с): {text[:120] if text else 'контекст пуст'}",
            reply_cautious="Уточни формулировку и подтверди её письменно.",
            reply_confident="Фиксируй сейчас: это критичный момент переговоров.",
            severity="info",
            timestamp=time.monotonic(),
            speaker="THEM",
            agent_name="Оркестратор",
            is_fallback=False,
            source_ts_end=recent[-1].ts_end if recent else 0.0,
        )

        if self.mic_speaking:
            self._enqueue_pending(card)
            return []

        self.telemetry.on_card_shown(card, shown_ts=card.source_ts_end or time.monotonic())
        return [card]

    async def on_direct_force_answer_segment(self, segment: TranscriptSegment) -> list[InsightCard]:
        if self.paused or not self.force_answer_mode:
            return []
        if not self._should_emit_direct_force_for_segment(segment):
            return []

        source_ts_end = segment.tsEnd if segment.tsEnd > 0 else time.monotonic()
        context = self._build_direct_force_context(speaker=segment.speaker, text=segment.text)
        cards = await self._generate_cards_for_profiles(
            profiles=[self.DIRECT_FORCE_AGENT_PROFILE],
            speaker=segment.speaker,
            trigger_reason="прямой LLM-поток: автоответ на реплику",
            context=context,
            source_ts_end=source_ts_end,
            force_mode=True,
        )
        if not cards:
            return []

        now = time.monotonic()
        self.last_direct_force_ts = now
        if segment.isFinal:
            self.direct_force_seen_utterances.append(segment.utteranceId)
        self.last_direct_force_text = normalize(segment.text)
        self.last_card_severity = self._max_severity(cards)
        self.recent_card_ts.append(now)
        self._trim_card_window(now)

        for card in cards:
            self.telemetry.on_card_shown(card, shown_ts=source_ts_end)
        return cards

    async def on_direct_force_answer_mic_event(self, event: MicEvent) -> list[InsightCard]:
        if self.paused or not self.force_answer_mode:
            return []
        if not self._should_emit_direct_force_for_mic_end(event):
            return []

        context = self._build_direct_force_context(
            speaker="ME",
            text="",
        )
        source_ts_end = event.timestamp if event.timestamp > 0 else time.monotonic()
        cards = await self._generate_cards_for_profiles(
            profiles=[self.DIRECT_FORCE_AGENT_PROFILE],
            speaker="ME",
            trigger_reason="прямой LLM-поток: завершена реплика пользователя",
            context=context,
            source_ts_end=source_ts_end,
            force_mode=True,
        )
        if not cards:
            return []

        now = time.monotonic()
        self.last_direct_force_ts = now
        self.last_card_severity = self._max_severity(cards)
        self.recent_card_ts.append(now)
        self._trim_card_window(now)

        for card in cards:
            self.telemetry.on_card_shown(card, shown_ts=source_ts_end)
        return cards

    def _should_trigger(self, score: float, segment: TranscriptSegment) -> bool:
        if self._is_excluded(segment):
            return False

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

    def _is_excluded(self, segment: TranscriptSegment) -> bool:
        if not self.excluded_phrases:
            return False
        text = normalize(segment.text)
        for phrase in self.excluded_phrases:
            if phrase and phrase in text:
                return True
        return False

    def _trim_card_window(self, now: float) -> None:
        window_start = now - 600
        while self.recent_card_ts and self.recent_card_ts[0] < window_start:
            self.recent_card_ts.popleft()

    def _build_trigger_reason(self, segment: TranscriptSegment, score: float) -> str:
        snippet = segment.text.strip().replace("\n", " ")[:64]
        return f"обнаружен важный момент (score={score:.2f}): {snippet}"

    def _build_force_answer_reason(self, segment: TranscriptSegment) -> str:
        snippet = segment.text.strip().replace("\n", " ")[:72]
        if segment.speaker == "ME":
            prefix = "ваш вопрос"
        else:
            prefix = "вопрос собеседника"
        return f"принудительный режим ответа: {prefix} -> {snippet}"

    def _build_force_context(self, segment: TranscriptSegment) -> str:
        context = self.raw_buffer.recent_text(max_items=20)
        line = f"{segment.speaker}: {segment.text}".strip()
        if not line:
            return context
        if not context:
            return line
        if line in context:
            return context
        return f"{context}\n{line}"

    def _looks_like_question(self, text: str) -> bool:
        t = normalize(text)
        if "?" in text:
            return True
        starters = ("как ", "когда ", "почему ", "зачем ", "что ", "кто ", "где ", "какой ", "какая ", "какие ", "можете ", "можно ", "есть ли ")
        return t.startswith(starters)

    def _looks_like_force_prompt(self, text: str) -> bool:
        t = normalize(text)
        if self._looks_like_question(text):
            return True

        if not t:
            return False
        tokens = t.split()
        question_tokens = {
            "как",
            "когда",
            "почему",
            "зачем",
            "что",
            "кто",
            "где",
            "какой",
            "какая",
            "какие",
            "сколько",
            "чем",
            "ли",
            "можно",
            "можете",
            "можешь",
            "нужно",
            "надо",
        }
        if any(token in question_tokens for token in tokens[:5]):
            return True
        if " ли " in f" {t} ":
            return True

        # В интервью вопросы часто звучат без "?".
        interview_markers = (
            "расскажите",
            "расскажи",
            "опишите",
            "опиши",
            "подскажите",
            "подскажи",
            "поясните",
            "поясни",
            "объясните",
            "объясни",
            "уточните",
            "уточни",
            "прокомментируйте",
            "прокомментируй",
            "ответьте",
            "ответь",
            "почему",
            "зачем",
            "какой",
            "какая",
            "какие",
            "когда",
            "где",
            "кто",
            "что",
            "можете",
            "подтвердите",
        )
        return any(marker in t for marker in interview_markers)

    def _should_force_answer(self, segment: TranscriptSegment) -> bool:
        if segment.utteranceId in self.force_answer_seen_utterances:
            return False

        if segment.speaker not in {"THEM", "THEM_A", "THEM_B", "ME"}:
            return False

        normalized = normalize(segment.text)

        if not segment.isFinal:
            # Partial-сегменты: генерируем реже и только для длинных фраз
            if len(normalized.split()) < 5:
                return False
            now = time.monotonic()
            if (now - self.last_force_answer_ts) < max(3.0, self.force_answer_min_interval_sec):
                return False
        else:
            if len(normalized) < 5:
                return False
            if len(normalized.split()) < 2:
                return False
            now = time.monotonic()
            if (now - self.last_force_answer_ts) < self.force_answer_min_interval_sec:
                return False

        # Для профиля "я кандидат" режим должен быть максимально надежным:
        # генерируем ответ почти на каждую содержательную реплику.
        # В онлайне сегменты приходят как THEM, в офлайн-режиме (mic-only) — как ME.
        if self.profile.id == "interview_candidate":
            return True

        # В офлайн-режиме (mic-only) сегменты приходят как ME.
        # В force-режиме отвечаем на вопросоподобные реплики пользователя.
        if segment.speaker == "ME":
            return self._looks_like_force_prompt(segment.text)

        return self._looks_like_force_prompt(segment.text)

    def _should_emit_force_cards_on_mic_end(self) -> bool:
        if self.paused or self.mic_speaking:
            return False
        if self.pending_queue:
            return False
        now = time.monotonic()
        return (now - self.last_force_answer_ts) >= max(2.0, self.force_answer_min_interval_sec)

    def _should_emit_direct_force_for_segment(self, segment: TranscriptSegment) -> bool:
        if segment.speaker not in {"THEM", "THEM_A", "THEM_B", "ME"}:
            return False
        if segment.isFinal and segment.utteranceId in self.direct_force_seen_utterances:
            return False

        normalized = normalize(segment.text)
        if len(normalized) < 5 or len(normalized.split()) < 2:
            return False
        if normalized == self.last_direct_force_text:
            return False

        now = time.monotonic()
        min_interval = self.direct_force_min_interval_sec if segment.isFinal else max(1.6, self.direct_force_min_interval_sec)
        if (now - self.last_direct_force_ts) < min_interval:
            return False

        if segment.speaker == "ME":
            return True

        if self.profile.id == "interview_candidate":
            return True

        return self._looks_like_force_prompt(segment.text)

    def _should_emit_direct_force_for_mic_end(self, event: MicEvent) -> bool:
        if event.eventType != "speech_end":
            return False
        if self.mic_speaking:
            return False
        now = time.monotonic()
        return (now - self.last_direct_force_ts) >= max(1.3, self.direct_force_min_interval_sec)

    def _build_direct_force_context(self, *, speaker: str, text: str) -> str:
        context = self.raw_buffer.recent_text(max_items=20)
        line = f"{speaker}: {text}".strip()
        if not text.strip():
            if context:
                return context
            return "Контекст ограничен. Пользователь завершил реплику."
        if not context:
            return line
        if line in context:
            return context
        return f"{context}\n{line}"

    def _slot_card_id(self, agent_name: str | None) -> str:
        base = (agent_name or "Оркестратор").strip().lower().replace(" ", "_")
        return f"slot::{base}"

    async def _generate_cards_for_profiles(
        self,
        *,
        profiles: list[tuple[str, str]],
        speaker: str,
        trigger_reason: str,
        context: str,
        source_ts_end: float,
        force_mode: bool,
    ) -> list[InsightCard]:
        tasks = [
            self.llm.build_card(
                scenario=self.profile.id,
                speaker=speaker,
                trigger_reason=trigger_reason,
                context=context,
                source_ts_end=source_ts_end,
                agent_name=agent_name,
                agent_instruction=agent_instruction,
            )
            for agent_name, agent_instruction in profiles
        ]
        results = await asyncio.gather(*tasks, return_exceptions=True)

        cards: list[InsightCard] = []
        for index, result in enumerate(results):
            agent_name = profiles[index][0]
            if isinstance(result, Exception):
                cards.append(
                    self._build_local_agent_fallback_card(
                        speaker=speaker,
                        trigger_reason=trigger_reason,
                        source_ts_end=source_ts_end,
                        context=context,
                        agent_name=agent_name,
                        force_mode=force_mode,
                    )
                )
                continue
            self.telemetry.on_llm_call(latency_ms=result.latency_ms, timed_out=result.timed_out)
            card = result.card
            card.id = self._slot_card_id(card.agent_name)
            cards.append(card)
        return cards

    def _build_local_agent_fallback_card(
        self,
        *,
        speaker: str,
        trigger_reason: str,
        source_ts_end: float,
        context: str,
        agent_name: str,
        force_mode: bool,
    ) -> InsightCard:
        brief = context.strip().splitlines()[-1] if context.strip() else "Контекст ограничен"
        lowered = agent_name.lower()

        if "психолог" in lowered:
            insight = f"Психология: в реплике слышно давление -> {brief[:96]}"
            reply_cautious = "Сохрани нейтральный тон и уточни факты вопроса."
            reply_confident = "Переведи разговор в измеримые критерии и срок."
            severity = "info"
        elif "оркестратор" in lowered:
            insight = f"Главный фокус сейчас: {brief[:110]}"
            reply_cautious = "Сформулируй ответ мягко и уточни ожидания собеседника."
            reply_confident = "Ответь по сути, зафиксируй срок и следующий шаг."
            severity = "warning"
        elif force_mode:
            insight = f"Прямой ответ на вопрос собеседника: {brief[:110]}"
            reply_cautious = "Дай короткий ответ и уточни ожидания."
            reply_confident = "Ответь по сути и зафиксируй следующий шаг."
            severity = "warning"
        else:
            insight = f"Ключевой момент: {brief[:110]}"
            reply_cautious = "Уточни формулировку и закрепи письменно."
            reply_confident = "Сразу зафиксируй договорённость в протоколе."
            severity = "warning"

        return InsightCard(
            id=self._slot_card_id(agent_name),
            scenario=self.profile.id,
            card_mode=self.profile.card_mode,
            trigger_reason=trigger_reason,
            insight=insight,
            reply_cautious=reply_cautious,
            reply_confident=reply_confident,
            severity=severity,
            timestamp=time.monotonic(),
            speaker=speaker,
            agent_name=agent_name,
            is_fallback=True,
            source_ts_end=source_ts_end,
        )

    def _max_severity(self, cards: list[InsightCard]) -> str:
        rank = {"info": 0, "warning": 1, "alert": 2}
        top = "info"
        for card in cards:
            if rank.get(card.severity, 0) > rank.get(top, 0):
                top = card.severity
        return top

    def _enqueue_pending(self, card: InsightCard) -> None:
        if len(self.pending_queue) >= self.pending_queue.maxlen:
            self.pending_queue.clear()
            summary = InsightCard(
                id=str(uuid.uuid4()),
                scenario=self.profile.id,
                card_mode=self.profile.card_mode,
                trigger_reason="очередь карточек переполнена",
                insight="20 важных моментов пока вы говорили.",
                reply_cautious="Сделайте короткую паузу, чтобы показать сводку.",
                reply_confident="Остановимся на 10 секунд и разберём сводку моментов.",
                severity="warning",
                timestamp=time.monotonic(),
                speaker="THEM",
                is_fallback=False,
                source_ts_end=time.monotonic(),
            )
            self.pending_queue.append(summary)
        else:
            self.pending_queue.append(card)

        self.telemetry.on_pending_queue_len(len(self.pending_queue))
