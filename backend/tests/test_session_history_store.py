import sqlite3
from pathlib import Path

from session_history_store import SessionHistoryStore


def test_session_history_store_upsert(tmp_path: Path) -> None:
    db_path = tmp_path / "sessions.sqlite3"
    store = SessionHistoryStore(db_path)

    store.save_session(
        session_id="s1",
        profile_id="negotiation",
        started_at=100.0,
        ended_at=200.0,
        total_cards=3,
        fallback_cards=1,
        export_json_path="/tmp/s1.json",
        report_md_path="/tmp/s1-report.md",
        report_pdf_path=None,
    )
    store.save_session(
        session_id="s1",
        profile_id="sales",
        started_at=100.0,
        ended_at=220.0,
        total_cards=4,
        fallback_cards=0,
        export_json_path="/tmp/s1.json",
        report_md_path="/tmp/s1-report.md",
        report_pdf_path="/tmp/s1-report.pdf",
    )

    with sqlite3.connect(db_path) as conn:
        row = conn.execute(
            """
            SELECT profile_id, ended_at, total_cards, fallback_cards, report_pdf_path
            FROM session_history
            WHERE session_id = ?
            """,
            ("s1",),
        ).fetchone()

    assert row == ("sales", 220.0, 4, 0, "/tmp/s1-report.pdf")
