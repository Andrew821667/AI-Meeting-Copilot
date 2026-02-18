from profile_loader import load_negotiation_profile
from trigger_scorer import TriggerScorer
from models import TranscriptSegment


def make_segment(text: str) -> TranscriptSegment:
    return TranscriptSegment(
        schemaVersion=1,
        seq=1,
        utteranceId="u1",
        isFinal=True,
        speaker="THEM",
        text=text,
        tsStart=0.0,
        tsEnd=1.0,
        speakerConfidence=0.9,
    )


def test_trigger_score_positive_keyword() -> None:
    scorer = TriggerScorer(load_negotiation_profile())
    score = scorer.compute(make_segment("Если переносим дедлайн, будет штраф"))
    assert score >= 0.60


def test_trigger_score_negative_rule_suppresses() -> None:
    scorer = TriggerScorer(load_negotiation_profile())
    score = scorer.compute(make_segment("Это без штрафа для вас"))
    assert score < 0.60
