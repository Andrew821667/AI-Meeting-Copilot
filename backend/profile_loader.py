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
    trigger_vocab: list[TriggerRule]
    negative_rules: list[NegativeRule]


def load_negotiation_profile() -> Profile:
    return Profile(
        id="negotiation",
        threshold=0.60,
        cooldown_sec=90,
        max_cards_per_10min=4,
        min_pause_sec=1.5,
        min_context_min=2,
        trigger_vocab=[
            TriggerRule(type="token", value="штраф", weight=0.90, aliases=["штрафа", "штрафом", "штрафные"]),
            TriggerRule(type="token", value="дедлайн", weight=0.80, aliases=["deadline", "dead line", "дед лайн"]),
            TriggerRule(type="token", value="скидка", weight=0.80, aliases=[]),
            TriggerRule(type="token", value="sla", weight=0.85, aliases=[]),
            TriggerRule(type="token", value="неустойка", weight=0.90, aliases=[]),
            TriggerRule(type="phrase", value="последнее предложение", weight=0.95, aliases=["последнее предложенье"]),
        ],
        negative_rules=[
            NegativeRule(type="phrase", value="без штрафа", suppress=["штраф"]),
            NegativeRule(type="phrase", value="не является дедлайном", suppress=["дедлайн"]),
        ],
    )
