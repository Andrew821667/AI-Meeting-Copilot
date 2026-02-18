from __future__ import annotations

import time
from collections import deque

from models import TranscriptSegment


class DiarizationGate:
    confidence_threshold = 0.70
    disable_cooldown_sec = 120

    def __init__(self) -> None:
        self.disabled_until_ts = 0.0
        self.switch_history: deque[tuple[float, str]] = deque(maxlen=20)
        self.last_speaker = ""

    def resolve_speaker(self, segment: TranscriptSegment) -> str:
        now = time.monotonic()

        if self._is_disabled(now):
            return "THEM"

        if segment.speakerConfidence < self.confidence_threshold:
            return "THEM"

        self._track_switch(now, segment.speaker)
        if self._is_thrashing(now):
            self._disable_temporarily(now)
            return "THEM"

        return segment.speaker

    def disabled_seconds_remaining(self) -> float:
        return max(0.0, self.disabled_until_ts - time.monotonic())

    def _track_switch(self, now: float, speaker: str) -> None:
        if not self.last_speaker:
            self.last_speaker = speaker
            return

        if speaker != self.last_speaker:
            self.switch_history.append((now, speaker))
            self.last_speaker = speaker

    def _is_disabled(self, now: float) -> bool:
        return now < self.disabled_until_ts

    def _disable_temporarily(self, now: float) -> None:
        self.disabled_until_ts = now + self.disable_cooldown_sec

    def _is_thrashing(self, now: float) -> bool:
        ten_sec_ago = now - 10.0
        recent = [x for x in self.switch_history if x[0] >= ten_sec_ago]
        return len(recent) > 5
