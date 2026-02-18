import sqlite3
from pathlib import Path

from feedback_store import FeedbackStore


def test_feedback_store_upsert_and_excluded_phrases(tmp_path: Path) -> None:
    db_path = tmp_path / "feedback.sqlite3"
    store = FeedbackStore(db_path)

    store.save_feedback(
        session_id="s1",
        card_id="c1",
        useful=True,
        excluded=False,
        trigger_reason="обнаружен важный момент: штраф",
        insight="Нужно зафиксировать штрафные условия",
    )
    store.save_feedback(
        session_id="s1",
        card_id="c1",
        useful=False,
        excluded=True,
        trigger_reason="обнаружен важный момент: штраф",
        insight="Не показывать похожее",
    )

    with sqlite3.connect(db_path) as conn:
        row = conn.execute(
            """
            SELECT useful, excluded, trigger_reason, insight
            FROM session_feedback
            WHERE session_id = ? AND card_id = ?
            """,
            ("s1", "c1"),
        ).fetchone()

    assert row == (0, 1, "обнаружен важный момент: штраф", "Не показывать похожее")

    store.save_excluded_phrase(
        profile_id="negotiation",
        phrase="последнее предложение по цене",
        normalized_phrase="последнее предложение по цене",
    )
    store.save_excluded_phrase(
        profile_id="negotiation",
        phrase="штраф 10%",
        normalized_phrase="штраф 10",
    )

    phrases = store.load_excluded_phrases(profile_id="negotiation")
    assert phrases == {"последнее предложение по цене", "штраф 10"}
