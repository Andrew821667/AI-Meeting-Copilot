from __future__ import annotations

import argparse
import asyncio
import json
import random
import time
from pathlib import Path

from models import MicEvent, TranscriptSegment
from orchestrator import TriggerOrchestrator
from profile_loader import load_profile
from telemetry import TelemetryCollector


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Синтетический стресс-тест оркестратора")
    parser.add_argument("--duration-min", type=int, default=90)
    parser.add_argument("--profile", default="negotiation")
    parser.add_argument("--inject-timeouts", type=float, default=0.0)
    parser.add_argument("--report", default="stress_report.json", help="Путь к JSON-отчёту")
    return parser.parse_args()


async def run(duration_min: int, profile_id: str, inject_timeouts: float, report: Path) -> None:
    telemetry = TelemetryCollector()
    orch = TriggerOrchestrator(load_profile(profile_id), telemetry=telemetry)
    # Accelerated thresholds for synthetic stress runs.
    orch.profile.min_context_min = 0
    orch.profile.cooldown_sec = 1
    orch.profile.max_cards_per_10min = 1000

    started = time.monotonic()
    end_ts = started + duration_min * 60
    seq = 0
    cards_generated = 0

    while time.monotonic() < end_ts:
        seq += 1
        now = time.monotonic() - started
        mic_event = MicEvent(
            schemaVersion=1,
            seq=seq,
            eventType="speech_end",
            timestamp=now,
            confidence=0.8,
            duration=1.2,
        )
        cards = await orch.on_mic_event(mic_event)
        cards_generated += len(cards)

        seq += 1
        tokens = ["дедлайн", "штраф", "скидка", "SLA", "последнее предложение"]
        text = f"Обсудим {random.choice(tokens)} и условия договора"
        seg = TranscriptSegment(
            schemaVersion=1,
            seq=seq,
            utteranceId=f"u-{seq}",
            isFinal=True,
            speaker="THEM",
            text=text,
            tsStart=now,
            tsEnd=now + 0.8,
            speakerConfidence=0.9,
        )

        # coarse timeout injection by extending llm sleep timeout behavior
        if random.random() < inject_timeouts:
            orch.llm.timeout_sec = 0.01
        else:
            orch.llm.timeout_sec = 3.0

        cards = await orch.on_transcript_segment(seg)
        cards_generated += len(cards)

        await asyncio.sleep(0.02)

    payload = {
        "duration_min": duration_min,
        "cards_generated": cards_generated,
        "metrics": telemetry.build_metrics(),
        "pending_queue_len": len(orch.pending_queue),
    }
    report.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")


def main() -> None:
    args = parse_args()
    asyncio.run(run(args.duration_min, args.profile, args.inject_timeouts, Path(args.report)))


if __name__ == "__main__":
    main()
