from __future__ import annotations

import argparse
import json
from pathlib import Path

from models import RawBufferEntry, TranscriptSegment
from profile_loader import load_profile
from raw_buffer import RawBuffer
from trigger_scorer import TriggerScorer


class ReplayMode:
    """Оффлайн-переигрывание решений триггеров по экспортированной сессии."""

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
            reason = "сработал"
            triggered = True

            if score < profile.threshold:
                triggered = False
                reason = "ниже порога"
            elif raw_buffer.duration_minutes() < profile.min_context_min:
                triggered = False
                reason = "недостаточный контекст"
            elif segment.utteranceId in seen_utterances:
                triggered = False
                reason = "дубликат реплики"
            elif (segment.tsEnd - last_trigger_ts) < profile.cooldown_sec:
                triggered = False
                reason = "пауза между срабатываниями"

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
    parser = argparse.ArgumentParser(description="Переигрывание триггеров по экспортированной сессии")
    parser.add_argument("--session", required=True, help="Путь к JSON-файлу экспортированной сессии")
    parser.add_argument("--profile", default="negotiation", help="Идентификатор профиля")
    parser.add_argument("--out", default="replay_report.json", help="Путь для выходного отчёта")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    replay = ReplayMode()
    rows = replay.replay(Path(args.session), args.profile)
    Path(args.out).write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
