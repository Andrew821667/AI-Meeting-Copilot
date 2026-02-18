from meeting_memory import MeetingMemoryUpdater
from models import TranscriptSegment


def make_segment(text: str, ts_end: float = 600.0) -> TranscriptSegment:
    return TranscriptSegment(
        schemaVersion=1,
        seq=1,
        utteranceId="u1",
        isFinal=True,
        speaker="THEM",
        text=text,
        tsStart=max(0.0, ts_end - 1.0),
        tsEnd=ts_end,
        speakerConfidence=0.9,
    )


def test_adaptive_update_on_high_score() -> None:
    u = MeetingMemoryUpdater()
    updated = u.maybe_update(segment=make_segment("Мы согласовали дедлайн"), score=0.95, last_card_severity=None)
    assert updated
    assert u.memory.decisions


def test_update_on_meeting_end_adds_summary() -> None:
    u = MeetingMemoryUpdater()
    memory = u.update_on_meeting_end(transcript=[make_segment("Есть риск штрафа")], cards=[], ended_ts=999)
    assert memory["summary_bullets"]
    assert memory["risks"]
