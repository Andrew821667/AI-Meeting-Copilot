from __future__ import annotations

import sqlite3
import time
from pathlib import Path


class SessionHistoryStore:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS session_history (
                    session_id TEXT PRIMARY KEY,
                    profile_id TEXT NOT NULL,
                    started_at REAL NOT NULL,
                    ended_at REAL NOT NULL,
                    total_cards INTEGER NOT NULL,
                    fallback_cards INTEGER NOT NULL,
                    export_json_path TEXT NOT NULL,
                    report_md_path TEXT NOT NULL,
                    report_pdf_path TEXT,
                    created_at REAL NOT NULL
                )
                """
            )
            conn.commit()

    def save_session(
        self,
        *,
        session_id: str,
        profile_id: str,
        started_at: float,
        ended_at: float,
        total_cards: int,
        fallback_cards: int,
        export_json_path: str,
        report_md_path: str,
        report_pdf_path: str | None,
    ) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT INTO session_history (
                    session_id, profile_id, started_at, ended_at,
                    total_cards, fallback_cards,
                    export_json_path, report_md_path, report_pdf_path,
                    created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id) DO UPDATE SET
                    profile_id=excluded.profile_id,
                    started_at=excluded.started_at,
                    ended_at=excluded.ended_at,
                    total_cards=excluded.total_cards,
                    fallback_cards=excluded.fallback_cards,
                    export_json_path=excluded.export_json_path,
                    report_md_path=excluded.report_md_path,
                    report_pdf_path=excluded.report_pdf_path,
                    created_at=excluded.created_at
                """,
                (
                    session_id,
                    profile_id,
                    started_at,
                    ended_at,
                    total_cards,
                    fallback_cards,
                    export_json_path,
                    report_md_path,
                    report_pdf_path,
                    time.time(),
                ),
            )
            conn.commit()
