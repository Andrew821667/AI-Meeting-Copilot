import json
from pathlib import Path

from replay_mode import ReplayMode


def test_replay_outputs_rows(tmp_path: Path) -> None:
    payload = {
        "session_id": "s1",
        "profile": "negotiation",
        "transcript": [
            {
                "schemaVersion": 1,
                "seq": 1,
                "utteranceId": "u1",
                "isFinal": True,
                "speaker": "THEM",
                "text": "Если сорвем дедлайн, будет штраф",
                "tsStart": 0.0,
                "tsEnd": 121.0,
                "speakerConfidence": 0.9,
            }
        ],
    }
    p = tmp_path / "session.json"
    p.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")

    rows = ReplayMode().replay(p, "negotiation")
    assert len(rows) == 1
    assert "triggered" in rows[0]
