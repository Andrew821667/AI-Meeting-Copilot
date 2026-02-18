from __future__ import annotations

import math
from collections import deque

from models import AudioLevelEvent, InsightCard, SystemStateEvent


def _percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    data = sorted(values)
    k = (len(data) - 1) * p
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return data[int(k)]
    return data[f] * (c - k) + data[c] * (k - f)


class TelemetryCollector:
    def __init__(self) -> None:
        self.total_cards = 0
        self.fallback_cards = 0
        self.dismissed_cards = 0
        self.useful_feedback_count = 0
        self.useless_feedback_count = 0
        self.excluded_feedback_count = 0

        self.api_timeouts = 0
        self.llm_discarded_responses = 0
        self.llm_canceled_after_send_rate = 0.0
        self.llm_latency_ms: list[float] = []

        self.card_show_latency_ms: list[float] = []
        self.pending_queue_max_len = 0

        self.audio_source_suspect_count = 0
        self._low_system_rms_streak = 0

        self.diarization_disabled_seconds = 0

        self.thermal_state_time_serious_seconds = 0.0
        self._last_system_state_ts = None
        self._last_thermal_state = None

        self.python_rss_peak_mb = 0

        self.asr_partial_latency_ms: list[float] = []
        self.asr_final_latency_ms: list[float] = []

    def on_llm_call(self, latency_ms: float, timed_out: bool) -> None:
        self.llm_latency_ms.append(latency_ms)
        if timed_out:
            self.api_timeouts += 1

    def on_pending_queue_len(self, value: int) -> None:
        self.pending_queue_max_len = max(self.pending_queue_max_len, value)

    def on_card_shown(self, card: InsightCard, shown_ts: float) -> None:
        self.total_cards += 1
        if card.is_fallback:
            self.fallback_cards += 1

        if card.source_ts_end > 0:
            latency = max(0.0, shown_ts - card.source_ts_end) * 1000
            self.card_show_latency_ms.append(latency)

    def on_card_feedback(self, *, useful: bool, excluded: bool) -> None:
        if useful:
            self.useful_feedback_count += 1
        else:
            self.useless_feedback_count += 1

        if excluded:
            self.excluded_feedback_count += 1

    def on_audio_level(self, event: AudioLevelEvent) -> None:
        if event.systemRms < 0.05:
            self._low_system_rms_streak += 1
            if self._low_system_rms_streak == 5:
                self.audio_source_suspect_count += 1
        else:
            self._low_system_rms_streak = 0

    def on_system_state(self, event: SystemStateEvent) -> None:
        if self._last_system_state_ts is not None and self._last_thermal_state in {"serious", "critical"}:
            delta = max(0.0, event.timestamp - self._last_system_state_ts)
            self.thermal_state_time_serious_seconds += delta

        self._last_system_state_ts = event.timestamp
        self._last_thermal_state = event.thermalState

    def set_python_rss_peak_mb(self, rss_peak_mb: int) -> None:
        self.python_rss_peak_mb = max(self.python_rss_peak_mb, rss_peak_mb)

    def build_metrics(self) -> dict:
        llm_timeout_rate = (self.api_timeouts / self.total_cards) if self.total_cards else 0.0

        return {
            "total_cards": self.total_cards,
            "fallback_cards": self.fallback_cards,
            "dismissed_cards": self.dismissed_cards,
            "useful_feedback_count": self.useful_feedback_count,
            "useless_feedback_count": self.useless_feedback_count,
            "excluded_feedback_count": self.excluded_feedback_count,
            "api_timeouts": self.api_timeouts,
            "llm_discarded_responses": self.llm_discarded_responses,
            "llm_canceled_after_send_rate": self.llm_canceled_after_send_rate,
            "avg_asr_partial_latency_ms": sum(self.asr_partial_latency_ms) / len(self.asr_partial_latency_ms)
            if self.asr_partial_latency_ms
            else 0,
            "avg_asr_final_latency_ms": sum(self.asr_final_latency_ms) / len(self.asr_final_latency_ms)
            if self.asr_final_latency_ms
            else 0,
            "avg_llm_latency_ms": sum(self.llm_latency_ms) / len(self.llm_latency_ms) if self.llm_latency_ms else 0,
            "llm_timeout_rate": llm_timeout_rate,
            "card_show_latency_p50_ms": _percentile(self.card_show_latency_ms, 0.5),
            "card_show_latency_p95_ms": _percentile(self.card_show_latency_ms, 0.95),
            "pending_queue_max_len": self.pending_queue_max_len,
            "audio_source_suspect_count": self.audio_source_suspect_count,
            "diarization_disabled_seconds": self.diarization_disabled_seconds,
            "thermal_state_time_serious_seconds": self.thermal_state_time_serious_seconds,
            "python_rss_peak_mb": self.python_rss_peak_mb,
        }
