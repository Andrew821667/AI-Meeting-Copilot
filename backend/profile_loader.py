from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TriggerRule:
    type: str
    value: str
    weight: float
    aliases: list[str] = field(default_factory=list)


@dataclass
class NegativeRule:
    type: str
    value: str
    suppress: list[str] = field(default_factory=list)


@dataclass
class Profile:
    id: str
    threshold: float
    cooldown_sec: float
    max_cards_per_10min: int
    min_pause_sec: float
    min_context_min: int
    card_mode: str
    trigger_vocab: list[TriggerRule]
    negative_rules: list[NegativeRule]


def _negotiation() -> Profile:
    return Profile(
        id="negotiation",
        threshold=0.60,
        cooldown_sec=90,
        max_cards_per_10min=4,
        min_pause_sec=1.5,
        min_context_min=2,
        card_mode="reply_suggestions",
        trigger_vocab=[
            TriggerRule(type="token", value="штраф", weight=0.90, aliases=["штрафа", "штрафом", "штрафные"]),
            TriggerRule(type="token", value="дедлайн", weight=0.80, aliases=["deadline", "dead line", "дед лайн"]),
            TriggerRule(type="token", value="скидка", weight=0.80),
            TriggerRule(type="token", value="sla", weight=0.85),
            TriggerRule(type="token", value="неустойка", weight=0.90),
            TriggerRule(type="phrase", value="последнее предложение", weight=0.95, aliases=["последнее предложенье"]),
        ],
        negative_rules=[
            NegativeRule(type="phrase", value="без штрафа", suppress=["штраф"]),
            NegativeRule(type="phrase", value="не является дедлайном", suppress=["дедлайн"]),
        ],
    )


def _interview_candidate() -> Profile:
    return Profile(
        id="interview_candidate",
        threshold=0.70,
        cooldown_sec=90,
        max_cards_per_10min=3,
        min_pause_sec=1.5,
        min_context_min=1,
        card_mode="reply_suggestions",
        trigger_vocab=[
            TriggerRule(type="phrase", value="расскажи о себе", weight=0.90),
            TriggerRule(type="phrase", value="слабые стороны", weight=0.95),
            TriggerRule(type="token", value="провал", weight=0.85),
            TriggerRule(type="token", value="конфликт", weight=0.80),
            TriggerRule(type="phrase", value="почему уходишь", weight=0.90),
            TriggerRule(type="token", value="зарплата", weight=0.85),
        ],
        negative_rules=[],
    )


def _interview_interviewer() -> Profile:
    return Profile(
        id="interview_interviewer",
        threshold=0.65,
        cooldown_sec=90,
        max_cards_per_10min=4,
        min_pause_sec=1.5,
        min_context_min=1,
        card_mode="questions_to_ask",
        trigger_vocab=[
            TriggerRule(type="phrase", value="мы делали", weight=0.70),
            TriggerRule(type="phrase", value="я отвечал за все", weight=0.85),
            TriggerRule(type="token", value="противоречие", weight=0.90),
            TriggerRule(type="token", value="уклонение", weight=0.85),
        ],
        negative_rules=[],
    )


def _consulting() -> Profile:
    return Profile(
        id="consulting",
        threshold=0.70,
        cooldown_sec=90,
        max_cards_per_10min=3,
        min_pause_sec=1.5,
        min_context_min=1,
        card_mode="questions_to_ask",
        trigger_vocab=[
            TriggerRule(type="token", value="требования", weight=0.75),
            TriggerRule(type="token", value="ограничения", weight=0.75),
            TriggerRule(type="token", value="бюджет", weight=0.80),
            TriggerRule(type="phrase", value="как сейчас", weight=0.80),
            TriggerRule(type="token", value="боль", weight=0.80),
            TriggerRule(type="phrase", value="не работает", weight=0.85),
        ],
        negative_rules=[],
    )


def _sales() -> Profile:
    return Profile(
        id="sales",
        threshold=0.65,
        cooldown_sec=90,
        max_cards_per_10min=4,
        min_pause_sec=1.5,
        min_context_min=1,
        card_mode="reply_suggestions",
        trigger_vocab=[
            TriggerRule(type="token", value="дорого", weight=0.90),
            TriggerRule(type="phrase", value="не сейчас", weight=0.85),
            TriggerRule(type="token", value="конкурент", weight=0.80),
            TriggerRule(type="phrase", value="нет бюджета", weight=0.90),
            TriggerRule(type="phrase", value="подумаем", weight=0.80),
        ],
        negative_rules=[],
    )


def _tech_sync() -> Profile:
    return Profile(
        id="tech_sync",
        threshold=0.65,
        cooldown_sec=90,
        max_cards_per_10min=5,
        min_pause_sec=1.5,
        min_context_min=1,
        card_mode="hypothesis_debug",
        trigger_vocab=[
            TriggerRule(type="token", value="ошибка", weight=0.80),
            TriggerRule(type="token", value="лог", weight=0.70),
            TriggerRule(type="token", value="деградация", weight=0.85),
            TriggerRule(type="token", value="блокер", weight=0.90),
            TriggerRule(type="token", value="latency", weight=0.80),
            TriggerRule(type="token", value="regression", weight=0.85),
            TriggerRule(type="token", value="hotfix", weight=0.90),
        ],
        negative_rules=[],
    )


_PROFILES = {
    "negotiation": _negotiation,
    "interview_candidate": _interview_candidate,
    "interview_interviewer": _interview_interviewer,
    "consulting": _consulting,
    "sales": _sales,
    "tech_sync": _tech_sync,
}


def load_profile(profile_id: str) -> Profile:
    factory = _PROFILES.get(profile_id, _negotiation)
    return factory()


def load_negotiation_profile() -> Profile:
    return _negotiation()


def list_profiles() -> list[str]:
    return list(_PROFILES.keys())


def apply_overrides(profile: Profile, overrides: dict | None) -> Profile:
    if not overrides:
        return profile

    # Defensive copy of profile object with optional runtime overrides.
    return Profile(
        id=profile.id,
        threshold=float(overrides.get("threshold", profile.threshold)),
        cooldown_sec=float(overrides.get("cooldown_sec", profile.cooldown_sec)),
        max_cards_per_10min=int(overrides.get("max_cards_per_10min", profile.max_cards_per_10min)),
        min_pause_sec=float(overrides.get("min_pause_sec", profile.min_pause_sec)),
        min_context_min=int(overrides.get("min_context_min", profile.min_context_min)),
        card_mode=profile.card_mode,
        trigger_vocab=profile.trigger_vocab,
        negative_rules=profile.negative_rules,
    )


def profile_runtime_settings(profile: Profile) -> dict:
    return {
        "threshold": profile.threshold,
        "cooldown_sec": profile.cooldown_sec,
        "max_cards_per_10min": profile.max_cards_per_10min,
        "min_pause_sec": profile.min_pause_sec,
        "min_context_min": profile.min_context_min,
        "card_mode": profile.card_mode,
    }
