from __future__ import annotations

import asyncio
import time
import uuid
from dataclasses import dataclass

from models import InsightCard


@dataclass
class LLMCallResult:
    card: InsightCard
    latency_ms: float
    timed_out: bool


class RealtimeLLMClient:
    def __init__(self, timeout_sec: float = 3.0) -> None:
        self.timeout_sec = timeout_sec

    async def build_card(self, scenario: str, speaker: str, trigger_reason: str, context: str, source_ts_end: float) -> LLMCallResult:
        started = time.perf_counter()
        try:
            card = await asyncio.wait_for(
                self._generate_card(
                    scenario=scenario,
                    speaker=speaker,
                    trigger_reason=trigger_reason,
                    context=context,
                    source_ts_end=source_ts_end,
                ),
                timeout=self.timeout_sec,
            )
            return LLMCallResult(card=card, latency_ms=(time.perf_counter() - started) * 1000, timed_out=False)
        except asyncio.TimeoutError:
            card = self._fallback_card(
                scenario=scenario,
                speaker=speaker,
                trigger_reason=trigger_reason,
                source_ts_end=source_ts_end,
            )
            return LLMCallResult(card=card, latency_ms=(time.perf_counter() - started) * 1000, timed_out=True)

    async def _generate_card(self, scenario: str, speaker: str, trigger_reason: str, context: str, source_ts_end: float) -> InsightCard:
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
            source_ts_end=source_ts_end,
        )

    def _fallback_card(self, scenario: str, speaker: str, trigger_reason: str, source_ts_end: float) -> InsightCard:
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
            source_ts_end=source_ts_end,
        )
