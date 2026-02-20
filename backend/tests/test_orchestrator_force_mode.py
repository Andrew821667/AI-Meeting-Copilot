import asyncio
import time
from typing import Optional

from llm_client import LLMTransport, RealtimeLLMClient
from models import InsightCard, MicEvent, TranscriptSegment
from orchestrator import TriggerOrchestrator
from profile_loader import apply_overrides, load_profile


class ForceModeTransport(LLMTransport):
    async def generate(self, *, prompt: str, timeout_sec: float) -> dict:
        if "Психолог" in prompt:
            return {
                "insight": "Психология: собеседник давит сроком.",
                "reply_cautious": "Сохраняю спокойствие и уточняю критерии.",
                "reply_confident": "Фиксирую рамки ответа и следующий шаг.",
                "severity": "info",
            }
        return {
            "insight": "Короткий ответ: беру задачу и называю срок.",
            "reply_cautious": "Подтвержу ожидания и приоритет.",
            "reply_confident": "Да, беру в работу и дам результат в обозначенный срок.",
            "severity": "warning",
        }

    async def generate_text(self, *, prompt: str, system: str, timeout_sec: float) -> str:
        return "Функции в Python — это именованные блоки кода, которые выполняют определённую задачу. Определяются с помощью ключевого слова def."


def _segment(*, utterance_id: str, is_final: bool, speaker: str = "THEM", text: Optional[str] = None) -> TranscriptSegment:
    return TranscriptSegment(
        schemaVersion=1,
        seq=1,
        utteranceId=utterance_id,
        isFinal=is_final,
        speaker=speaker,
        text=text or "Почему вы хотите работать именно у нас и каков ваш опыт?",
        tsStart=10.0,
        tsEnd=12.2,
        speakerConfidence=0.95,
    )


def _orchestrator() -> TriggerOrchestrator:
    profile = apply_overrides(load_profile("interview_candidate"), {"force_answer_mode": True})
    orchestrator = TriggerOrchestrator(profile)
    orchestrator.llm = RealtimeLLMClient(timeout_sec=1.0, transport=ForceModeTransport())
    return orchestrator


def _mic_event(event_type: str = "speech_end", ts: float = 15.0) -> MicEvent:
    return MicEvent(
        schemaVersion=1,
        seq=101,
        eventType=event_type,
        timestamp=ts,
        confidence=0.93,
        duration=1.2,
    )


def test_should_force_answer_accepts_final_segment() -> None:
    """_should_force_answer возвращает True для final-сегмента с достаточным текстом."""
    orchestrator = _orchestrator()
    segment = _segment(utterance_id="u-1", is_final=True)
    assert orchestrator.force_answer_mode is True
    assert orchestrator._should_force_answer(segment) is True


def test_should_force_answer_rejects_short_partial() -> None:
    """Короткий partial (< 5 слов) отклоняется."""
    orchestrator = _orchestrator()
    short = _segment(utterance_id="u-2", is_final=False, text="Ну да")
    assert orchestrator._should_force_answer(short) is False


def test_should_force_answer_rejects_seen_utterance() -> None:
    """Уже обработанный utterance отклоняется."""
    orchestrator = _orchestrator()
    orchestrator.force_answer_seen_utterances.append("u-3")
    segment = _segment(utterance_id="u-3", is_final=True)
    assert orchestrator._should_force_answer(segment) is False


def test_build_answer_card_returns_direct_answer() -> None:
    """build_answer_card возвращает карточку с card_mode=direct_answer."""
    orchestrator = _orchestrator()
    seg = _segment(utterance_id="u-4", is_final=True, text="Расскажите про функции в Python")
    context = orchestrator._build_force_context(seg)
    trigger_reason = orchestrator._build_force_answer_reason(seg)

    result = asyncio.run(orchestrator.llm.build_answer_card(
        scenario=orchestrator.profile.id,
        speaker=seg.speaker,
        trigger_reason=trigger_reason,
        context=context,
        question_text=seg.text,
        source_ts_end=seg.tsEnd,
    ))
    card = result.card
    assert card.card_mode == "direct_answer"
    assert card.agent_name == "Ответы на вопросы"
    assert "Python" in card.insight or "функци" in card.insight.lower()
    assert card.reply_cautious == ""
    assert card.reply_confident == ""


def test_ingest_segment_to_buffers() -> None:
    """_ingest_segment_to_buffers добавляет сегмент в raw_buffer и transcript_history."""
    orchestrator = _orchestrator()
    seg = _segment(utterance_id="u-5", is_final=True)
    orchestrator._ingest_segment_to_buffers(seg)
    assert len(orchestrator.transcript_history) == 1
    assert orchestrator.raw_buffer.recent_text(max_items=5) != ""


def test_force_mode_activated_bootstrap_card() -> None:
    orchestrator = _orchestrator()
    cards = asyncio.run(orchestrator.on_force_mode_activated())
    assert len(cards) == 1
    assert cards[0].agent_name == "Ответы на вопросы"
    assert cards[0].card_mode == "direct_answer"


def test_non_force_segment_still_processed() -> None:
    """В обычном режиме (не force) on_transcript_segment работает без изменений."""
    profile = apply_overrides(load_profile("interview_candidate"), {"force_answer_mode": False})
    orchestrator = TriggerOrchestrator(profile)
    orchestrator.llm = RealtimeLLMClient(timeout_sec=1.0, transport=ForceModeTransport())

    seg = _segment(utterance_id="u-6", is_final=True)
    cards = asyncio.run(orchestrator.on_transcript_segment(seg))
    # Без force mode — обычная обработка (может вернуть карточки через trigger scoring)
    assert isinstance(cards, list)
