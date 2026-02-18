from telemetry import TelemetryCollector
from models import AudioLevelEvent


def test_audio_source_suspect_counter() -> None:
    t = TelemetryCollector()

    for i in range(5):
        t.on_audio_level(
            AudioLevelEvent(
                schemaVersion=1,
                seq=i + 1,
                timestamp=float(i),
                micRms=0.2,
                systemRms=0.01,
            )
        )

    metrics = t.build_metrics()
    assert metrics["audio_source_suspect_count"] == 1


def test_card_latency_percentiles() -> None:
    t = TelemetryCollector()
    # emulate latencies in ms directly
    t.card_show_latency_ms = [1000, 2000, 3000, 4000]
    metrics = t.build_metrics()
    assert metrics["card_show_latency_p50_ms"] == 2500
    assert metrics["card_show_latency_p95_ms"] > 3500
