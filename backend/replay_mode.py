from __future__ import annotations

import argparse
import json
from pathlib import Path

from models import RawBufferEntry, TranscriptSegment
from profile_loader import load_profile
from raw_buffer import RawBuffer
from trigger_scorer import TriggerScorer


class ReplayMode:
    """Offline trigger replay for one exported session JSON."""

    def replay(self, session_json: Path, profile_id: str) -> list[dict]:
        payload = json.loads(session_json.read_text(encoding="utf-8"))
        profile = load_profile(profile_id)
        scorer = TriggerScorer(profile)
        raw_buffer = RawBuffer(max_duration_sec=300)

        seen_utterances: set[str] = set()
        last_trigger_ts = 0.0
        rows: list[dict] = []

        transcript = payload.get("transcript", [])
        for raw in transcript:
            segment = TranscriptSegment(**raw)
            if not segment.isFinal:
                continue

            raw_buffer.append(
                RawBufferEntry(
                    speaker=segment.speaker,
                    text=segment.text,
                    ts_start=segment.tsStart,
                    ts_end=segment.tsEnd,
                )
            )

            score = scorer.compute(segment)
            reason = "ok"
            triggered = True

            if score < profile.threshold:
                triggered = False
                reason = "threshold_miss"
            elif raw_buffer.duration_minutes() < profile.min_context_min:
                triggered = False
                reason = "insufficient_context"
            elif segment.utteranceId in seen_utterances:
                triggered = False
                reason = "duplicate"
            elif (segment.tsEnd - last_trigger_ts) < profile.cooldown_sec:
                triggered = False
                reason = "cooldown"

            if triggered:
                last_trigger_ts = segment.tsEnd
                seen_utterances.add(segment.utteranceId)

            rows.append(
                {
                    "text": segment.text,
                    "keyword_score": scorer.last_breakdown.keyword_score,
                    "semantic_shift": scorer.last_breakdown.semantic_shift,
                    "emotion_boost": scorer.last_breakdown.emotion_boost,
                    "total_score": score,
                    "threshold": profile.threshold,
                    "triggered": triggered,
                    "reason": reason,
                }
            )

        return rows


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Replay trigger decisions for one exported session")
    parser.add_argument("--session", required=True, help="Path to exported session JSON")
    parser.add_argument("--profile", default="negotiation", help="Profile id")
    parser.add_argument("--out", default="replay_report.json", help="Output JSON report path")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    replay = ReplayMode()
    rows = replay.replay(Path(args.session), args.profile)
    Path(args.out).write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
