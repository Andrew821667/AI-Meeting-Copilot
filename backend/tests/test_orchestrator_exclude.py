from models import RawBufferEntry, TranscriptSegment
from orchestrator import TriggerOrchestrator
from profile_loader import load_negotiation_profile


def test_excluded_phrase_blocks_trigger() -> None:
    profile = load_negotiation_profile()
    orchestrator = TriggerOrchestrator(profile)

    orchestrator.raw_buffer.append(RawBufferEntry(speaker="THEM", text="Вводный контекст", ts_start=0.0, ts_end=1.0))
    orchestrator.raw_buffer.append(
        RawBufferEntry(speaker="THEM", text="Обсуждаем условия", ts_start=121.0, ts_end=122.0)
    )

    segment = TranscriptSegment(
        schemaVersion=1,
        seq=10,
        utteranceId="u10",
        isFinal=True,
        speaker="THEM",
        text="В случае нарушения дедлайна штраф составит 10 процентов",
        tsStart=122.0,
        tsEnd=125.0,
        speakerConfidence=0.95,
    )

    score = orchestrator.scorer.compute(segment)
    assert score >= profile.threshold
    orchestrator.last_trigger_ts = -1_000_000_000.0
    assert orchestrator._is_excluded(segment) is False
    assert orchestrator._should_trigger(score=score, segment=segment) is True

    normalized = orchestrator.add_excluded_phrase("штраф составит 10 процентов")
    assert normalized is not None
    assert orchestrator._is_excluded(segment) is True
    assert orchestrator._should_trigger(score=score, segment=segment) is False
