from __future__ import annotations

from collections import deque
from dataclasses import dataclass

from models import RawBufferEntry


@dataclass
class RawBuffer:
    max_duration_sec: int = 300

    def __post_init__(self) -> None:
        self.entries: deque[RawBufferEntry] = deque()

    def append(self, entry: RawBufferEntry) -> None:
        self.entries.append(entry)
        self._trim()

    def duration_minutes(self) -> float:
        if not self.entries:
            return 0.0
        return max(0.0, self.entries[-1].ts_end - self.entries[0].ts_start) / 60.0

    def recent_text(self, max_items: int = 20) -> str:
        tail = list(self.entries)[-max_items:]
        return "\n".join(f"{e.speaker}: {e.text}" for e in tail)

    def last_seconds(self, seconds: int) -> list[RawBufferEntry]:
        if not self.entries:
            return []
        end = self.entries[-1].ts_end
        start = max(0.0, end - seconds)
        return [e for e in self.entries if e.ts_end >= start]

    def _trim(self) -> None:
        if not self.entries:
            return
        end = self.entries[-1].ts_end
        cutoff = max(0.0, end - float(self.max_duration_sec))
        while self.entries and self.entries[0].ts_end < cutoff:
            self.entries.popleft()
