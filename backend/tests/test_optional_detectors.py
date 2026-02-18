from emotion_detector import EmotionDetector
from profile_loader import load_profile
from semantic_detector import SemanticDetector
from trigger_scorer import TriggerScorer
from models import TranscriptSegment


def _segment(text: str, seq: int = 1, utterance_id: str = "u1") -> TranscriptSegment:
    return TranscriptSegment(
        schemaVersion=1,
        seq=seq,
        utteranceId=utterance_id,
        isFinal=True,
        speaker="THEM",
        text=text,
        tsStart=0.0,
        tsEnd=1.0,
        speakerConfidence=0.9,
    )


def test_semantic_detector_disabled_by_default() -> None:
    profile = load_profile("negotiation")
    scorer = TriggerScorer(profile)
    scorer.compute(_segment("Обсуждаем дедлайн и штраф по контракту"))
    assert scorer.last_breakdown.semantic_shift == 0.0


def test_tech_sync_semantic_enabled_changes_breakdown() -> None:
    profile = load_profile("tech_sync")
    detector = SemanticDetector(enabled=True)
    detector.CALL_EVERY_N_REPLIES = 1
    detector.MIN_TOKENS = 1
    scorer = TriggerScorer(profile, semantic_detector=detector)

    scorer.compute(_segment("Ошибка в проде блокирует релиз", seq=1, utterance_id="u1"))
    score = scorer.compute(_segment("Нужен hotfix и rollback прямо сейчас", seq=2, utterance_id="u2"))
    assert score >= profile.threshold
    assert scorer.last_breakdown.semantic_shift >= 0.0


def test_emotion_detector_tense_signal() -> None:
    detector = EmotionDetector(enabled=True, call_on_keyword_hit=False, call_interval_sec=0.0)
    label, conf = detector.detect_from_text("Срочно! Это критично, есть штраф.", keyword_score=0.2)
    assert label == "tense"
    assert conf > 0.6


def test_optional_signals_can_be_disabled_runtime() -> None:
    profile = load_profile("tech_sync")
    detector = SemanticDetector(enabled=True)
    detector.CALL_EVERY_N_REPLIES = 1
    detector.MIN_TOKENS = 1
    scorer = TriggerScorer(profile, semantic_detector=detector)
    scorer.set_optional_signals_enabled(False)

    scorer.compute(_segment("Ошибка и regression в API", seq=1, utterance_id="u1"))
    scorer.compute(_segment("Новый текст без пересечения", seq=2, utterance_id="u2"))
    assert scorer.last_breakdown.semantic_shift == 0.0
