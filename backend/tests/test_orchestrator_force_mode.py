import asyncio
from typing import Optional

from llm_client import LLMTransport, RealtimeLLMClient
from models import MicEvent, TranscriptSegment
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


def test_force_mode_generates_three_cards() -> None:
    orchestrator = _orchestrator()
    segment = _segment(utterance_id="u-force-1", is_final=True)
    assert orchestrator.force_answer_mode is True
    assert orchestrator._should_force_answer(segment) is True
    cards = asyncio.run(orchestrator.on_transcript_segment(segment))

    assert len(cards) == 2
    assert {card.agent_name for card in cards} == {"Оркестратор", "Психолог"}
    assert {card.id for card in cards} == {"slot::оркестратор", "slot::психолог"}


def test_force_mode_ignores_partial_segments() -> None:
    orchestrator = _orchestrator()

    partial_segment = _segment(utterance_id="u-force-2", is_final=False)
    final_segment = _segment(utterance_id="u-force-2", is_final=True)

    partial_cards = asyncio.run(orchestrator.on_transcript_segment(partial_segment))
    assert partial_cards == []

    assert orchestrator._should_force_answer(final_segment) is True
    final_cards = asyncio.run(orchestrator.on_transcript_segment(final_segment))
    assert len(final_cards) == 2


def test_force_mode_accepts_me_question_as_offline_prompt() -> None:
    orchestrator = _orchestrator()
    cards = asyncio.run(
        orchestrator.on_transcript_segment(
            _segment(
                utterance_id="u-force-3",
                is_final=True,
                speaker="ME",
                text="Почему вы выбрали именно этот стек и как оцените мои риски?",
            )
        )
    )
    assert len(cards) == 2


def test_force_mode_ignores_me_non_question() -> None:
    orchestrator = _orchestrator()
    cards = asyncio.run(
        orchestrator.on_transcript_segment(
            _segment(
                utterance_id="u-force-4",
                is_final=True,
                speaker="ME",
                text="Да, хорошо, договорились и продолжим по плану",
            )
        )
    )
    assert cards == []


def test_force_mode_activated_bootstrap_cards() -> None:
    orchestrator = _orchestrator()
    cards = asyncio.run(orchestrator.on_force_mode_activated())
    assert len(cards) == 3
    assert {card.agent_name for card in cards} == {"Оркестратор", "Принудительный ответ", "Психолог"}


def test_force_mode_generates_cards_after_me_speech_end_event() -> None:
    orchestrator = _orchestrator()

    # Создаём контекст и сбрасываем cooldown для проверки mic-speech_end пути.
    _ = asyncio.run(orchestrator.on_transcript_segment(_segment(utterance_id="u-force-ctx", is_final=True)))
    orchestrator.last_force_answer_ts = -1_000_000_000.0

    cards = asyncio.run(orchestrator.on_mic_event(_mic_event("speech_end", ts=22.0)))
    assert len(cards) == 2
    assert {card.agent_name for card in cards} == {"Оркестратор", "Психолог"}


def test_direct_force_stream_returns_force_card_for_final_segment() -> None:
    orchestrator = _orchestrator()
    cards = asyncio.run(
        orchestrator.on_direct_force_answer_segment(
            _segment(
                utterance_id="u-force-direct-1",
                is_final=True,
                speaker="ME",
                text="Как лучше ответить на вопрос о слабых сторонах?",
            )
        )
    )
    assert len(cards) == 1
    assert cards[0].agent_name == "Принудительный ответ"
    assert cards[0].id == "slot::принудительный_ответ"


def test_direct_force_stream_returns_force_card_on_mic_end() -> None:
    orchestrator = _orchestrator()
    orchestrator.last_direct_force_ts = -1_000_000_000.0
    cards = asyncio.run(orchestrator.on_direct_force_answer_mic_event(_mic_event("speech_end", ts=31.0)))
    assert len(cards) == 1
    assert cards[0].agent_name == "Принудительный ответ"
