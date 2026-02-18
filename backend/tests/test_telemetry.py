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


def test_dynamic_timeout_warning_on_high_recent_p95() -> None:
    t = TelemetryCollector()
    t.on_llm_call(latency_ms=2100, timed_out=False)
    t.on_llm_call(latency_ms=2300, timed_out=False)
    t.on_llm_call(latency_ms=2200, timed_out=False)

    warnings = t.consume_runtime_warnings()
    assert len(warnings) == 1
    assert "LLM отвечает медленно" in warnings[0]
    assert t.build_metrics()["dynamic_timeout_warning_count"] == 1

    # No new LLM call: no duplicate warning.
    assert t.consume_runtime_warnings() == []

    # Recovery after fast calls resets active warning state.
    t.on_llm_call(latency_ms=400, timed_out=False)
    t.on_llm_call(latency_ms=500, timed_out=False)
    t.on_llm_call(latency_ms=450, timed_out=False)
    assert t.consume_runtime_warnings() == []
