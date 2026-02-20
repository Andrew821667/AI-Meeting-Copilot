from __future__ import annotations

import json
from dataclasses import asdict
from pathlib import Path

from models import InsightCard, TranscriptSegment


def export_session_json(
    exports_dir: Path,
    session_id: str,
    profile: str,
    started_at: float,
    ended_at: float,
    transcript: list[TranscriptSegment],
    cards: list[InsightCard],
    meeting_memory: dict,
    metrics: dict,
    settings: dict,
    audio_paths: dict | None = None,
) -> Path:
    exports_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "session_id": session_id,
        "profile": profile,
        "started_at": started_at,
        "ended_at": ended_at,
        "transcript": [asdict(x) for x in transcript],
        "cards_shown": [asdict(x) for x in cards],
        "meeting_memory": meeting_memory,
        "metrics": metrics,
        "settings": settings,
    }
    if audio_paths:
        payload["audio_paths"] = audio_paths

    target = exports_dir / f"{session_id}.json"
    target.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    return target
