from profile_loader import apply_overrides, load_profile, profile_runtime_settings


def test_profile_overrides_applied() -> None:
    base = load_profile("negotiation")
    updated = apply_overrides(base, {"threshold": 0.77, "cooldown_sec": 15, "min_pause_sec": 2.2})

    assert updated.threshold == 0.77
    assert updated.cooldown_sec == 15
    assert updated.min_pause_sec == 2.2
    assert updated.max_cards_per_10min == base.max_cards_per_10min


def test_optional_detector_flags_in_runtime_settings() -> None:
    profile = load_profile("tech_sync")
    runtime = profile_runtime_settings(profile)
    assert "semantic_enabled" in runtime
    assert "emotion_enabled" in runtime
    assert runtime["semantic_enabled"] is True
