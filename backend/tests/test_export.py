from pathlib import Path

from models import InsightCard, TranscriptSegment
from postfactum import build_markdown_report, build_meeting_memory
from session_export import export_session_json


def test_export_session_json(tmp_path: Path) -> None:
    transcript = [
        TranscriptSegment(
            schemaVersion=1,
            seq=1,
            utteranceId="u1",
            isFinal=True,
            speaker="THEM",
            text="Мы согласовали дедлайн и зафиксировали решение.",
            tsStart=0.0,
            tsEnd=1.2,
            speakerConfidence=0.9,
        )
    ]
    cards = [
        InsightCard(
            id="c1",
            scenario="negotiation",
            card_mode="reply_suggestions",
            trigger_reason="trigger",
            insight="Риск по дедлайну",
            reply_cautious="...",
            reply_confident="...",
            severity="warning",
            timestamp=1.2,
            speaker="THEM",
        )
    ]
    memory = build_meeting_memory(transcript, cards)
    metrics = {"total_cards": 1}

    path = export_session_json(
        exports_dir=tmp_path,
        session_id="s1",
        profile="negotiation",
        started_at=1,
        ended_at=2,
        transcript=transcript,
        cards=cards,
        meeting_memory=memory,
        metrics=metrics,
        settings={"threshold": 0.6},
    )

    assert path.exists()
    assert path.name == "s1.json"


def test_markdown_report_contains_sections() -> None:
    report = build_markdown_report(
        session_id="s1",
        profile="negotiation",
        meeting_memory={
            "summary_bullets": ["x"],
            "decisions": ["d"],
            "risks": ["r"],
            "open_questions": ["q"],
            "action_items": ["a"],
        },
        cards=[],
        metrics={"total_cards": 0},
    )
    assert "## Решения" in report
    assert "## Метрики" in report
