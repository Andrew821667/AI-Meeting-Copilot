from deepfilter_ab import compare


def test_deepfilter_ab_decision_enable() -> None:
    baseline = [
        {
            "reference": "это тестовая фраза без шума",
            "hypothesis": "это тестовая фраза без шум",
            "hallucinated": False,
            "latency_ms": 120,
            "intelligibility": 3.9,
        }
    ]
    candidate = [
        {
            "reference": "это тестовая фраза без шума",
            "hypothesis": "это тестовая фраза без шума",
            "hallucinated": False,
            "latency_ms": 140,
            "intelligibility": 4.3,
        }
    ]

    report = compare(baseline, candidate)
    assert report["decision"] == "enable"
    assert report["checks"]["latency_delta_le_40ms"] is True


def test_deepfilter_ab_decision_keep_off_on_latency() -> None:
    baseline = [
        {"reference": "a b c", "hypothesis": "a b c", "hallucinated": False, "latency_ms": 100, "intelligibility": 4.1}
    ]
    candidate = [
        {"reference": "a b c", "hypothesis": "a b c", "hallucinated": False, "latency_ms": 180, "intelligibility": 4.2}
    ]
    report = compare(baseline, candidate)
    assert report["decision"] == "keep_off"
    assert report["checks"]["latency_delta_le_40ms"] is False
