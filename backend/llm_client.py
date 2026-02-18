from __future__ import annotations

import asyncio
import uuid

from models import InsightCard


class RealtimeLLMClient:
    def __init__(self, timeout_sec: float = 3.0) -> None:
        self.timeout_sec = timeout_sec

    async def build_card(self, scenario: str, speaker: str, trigger_reason: str, context: str) -> InsightCard:
        try:
            return await asyncio.wait_for(
                self._generate_card(scenario=scenario, speaker=speaker, trigger_reason=trigger_reason, context=context),
                timeout=self.timeout_sec,
            )
        except asyncio.TimeoutError:
            return self._fallback_card(scenario=scenario, speaker=speaker, trigger_reason=trigger_reason)

    async def _generate_card(self, scenario: str, speaker: str, trigger_reason: str, context: str) -> InsightCard:
        # Local deterministic placeholder for Stage 2.
        await asyncio.sleep(0.20)
        brief = context.strip().splitlines()[-1] if context.strip() else "Контекст ограничен"
        return InsightCard(
            id=str(uuid.uuid4()),
            scenario=scenario,
            card_mode="reply_suggestions",
            trigger_reason=trigger_reason,
            insight=f"Зафиксируй риск: {brief[:120]}",
            reply_cautious="Уточним формулировку и закрепим письменно.",
            reply_confident="Предлагаю зафиксировать это в протоколе встречи прямо сейчас.",
            severity="warning",
            timestamp=asyncio.get_running_loop().time(),
            speaker=speaker,
            is_fallback=False,
        )

    def _fallback_card(self, scenario: str, speaker: str, trigger_reason: str) -> InsightCard:
        return InsightCard(
            id=str(uuid.uuid4()),
            scenario=scenario,
            card_mode="reply_suggestions",
            trigger_reason=trigger_reason,
            insight="API недоступен: используй осторожную фиксацию условий письменно.",
            reply_cautious="Давайте подтвердим детали письменно, чтобы не потерять условия.",
            reply_confident="Фиксируем этот пункт письменно сейчас и двигаемся дальше.",
            severity="warning",
            timestamp=asyncio.get_running_loop().time(),
            speaker=speaker,
            is_fallback=True,
        )
