from __future__ import annotations

import sqlite3
import time
from pathlib import Path


class FeedbackStore:
    def __init__(self, db_path: Path) -> None:
        self.db_path = db_path
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS session_feedback (
                    session_id TEXT NOT NULL,
                    card_id TEXT NOT NULL,
                    useful INTEGER NOT NULL,
                    excluded INTEGER NOT NULL,
                    trigger_reason TEXT NOT NULL,
                    insight TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    PRIMARY KEY(session_id, card_id)
                )
                """
            )
            conn.execute(
                """
                CREATE TABLE IF NOT EXISTS excluded_phrases (
                    profile_id TEXT NOT NULL,
                    phrase TEXT NOT NULL,
                    normalized_phrase TEXT NOT NULL,
                    created_at REAL NOT NULL,
                    PRIMARY KEY(profile_id, normalized_phrase)
                )
                """
            )
            conn.commit()

    def save_feedback(
        self,
        *,
        session_id: str,
        card_id: str,
        useful: bool,
        excluded: bool,
        trigger_reason: str,
        insight: str,
    ) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT INTO session_feedback (
                    session_id, card_id, useful, excluded, trigger_reason, insight, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(session_id, card_id) DO UPDATE SET
                    useful=excluded.useful,
                    excluded=excluded.excluded,
                    trigger_reason=excluded.trigger_reason,
                    insight=excluded.insight,
                    created_at=excluded.created_at
                """,
                (
                    session_id,
                    card_id,
                    int(useful),
                    int(excluded),
                    trigger_reason,
                    insight,
                    time.time(),
                ),
            )
            conn.commit()

    def save_excluded_phrase(self, *, profile_id: str, phrase: str, normalized_phrase: str) -> None:
        with sqlite3.connect(self.db_path) as conn:
            conn.execute(
                """
                INSERT INTO excluded_phrases (
                    profile_id, phrase, normalized_phrase, created_at
                ) VALUES (?, ?, ?, ?)
                ON CONFLICT(profile_id, normalized_phrase) DO UPDATE SET
                    phrase=excluded.phrase,
                    created_at=excluded.created_at
                """,
                (
                    profile_id,
                    phrase,
                    normalized_phrase,
                    time.time(),
                ),
            )
            conn.commit()

    def load_excluded_phrases(self, *, profile_id: str) -> set[str]:
        with sqlite3.connect(self.db_path) as conn:
            rows = conn.execute(
                """
                SELECT normalized_phrase
                FROM excluded_phrases
                WHERE profile_id = ?
                """,
                (profile_id,),
            ).fetchall()
        return {row[0] for row in rows}
