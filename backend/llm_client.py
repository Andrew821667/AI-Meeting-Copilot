from __future__ import annotations

import asyncio
import json
import os
import time
import uuid
from dataclasses import dataclass

from models import InsightCard

try:
    from openai import AsyncOpenAI  # type: ignore
except Exception:  # pragma: no cover
    AsyncOpenAI = None


@dataclass
class LLMCallResult:
    card: InsightCard
    latency_ms: float
    timed_out: bool


class LLMTransport:
    async def generate(self, *, prompt: str, timeout_sec: float) -> dict:
        raise NotImplementedError


class DeepSeekTransport(LLMTransport):
    def __init__(
        self,
        *,
        api_key: str,
        model: str,
        base_url: str,
        temperature: float,
        max_tokens: int,
    ) -> None:
        if AsyncOpenAI is None:
            raise RuntimeError("openai package is unavailable")

        self.model = model
        self.temperature = temperature
        self.max_tokens = max_tokens
        self.client = AsyncOpenAI(api_key=api_key, base_url=base_url)

    async def generate(self, *, prompt: str, timeout_sec: float) -> dict:
        response = await asyncio.wait_for(
            self.client.chat.completions.create(
                model=self.model,
                temperature=self.temperature,
                max_tokens=self.max_tokens,
                response_format={"type": "json_object"},
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "Ты ассистент встреч. Отвечай только валидным JSON "
                            "с полями insight, reply_cautious, reply_confident, trigger_reason, severity."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
            ),
            timeout=timeout_sec,
        )

        raw_content = (response.choices[0].message.content or "").strip()
        content = self._extract_json_text(raw_content)
        if not content:
            return {}
        return json.loads(content)

    @staticmethod
    def _extract_json_text(raw: str) -> str:
        text = raw.strip()
        if not text:
            return ""

        if text.startswith("```"):
            lines = text.splitlines()
            if len(lines) >= 3 and lines[-1].strip().startswith("```"):
                first = lines[0].strip().lower()
                body = "\n".join(lines[1:-1]).strip()
                if first.startswith("```json") or first == "```":
                    return body

        return text


class RealtimeLLMClient:
    def __init__(self, timeout_sec: float = 3.0, transport: LLMTransport | None = None) -> None:
        self.timeout_sec = timeout_sec
        self.transport = transport

    @classmethod
    def from_env(cls, timeout_sec: float = 3.0) -> "RealtimeLLMClient":
        api_key = os.environ.get("AIMC_DEEPSEEK_API_KEY", "").strip()
        if not api_key:
            return cls(timeout_sec=timeout_sec, transport=None)

        model = os.environ.get("AIMC_DEEPSEEK_MODEL", "deepseek-chat").strip() or "deepseek-chat"
        base_url = os.environ.get("AIMC_DEEPSEEK_BASE_URL", "https://api.deepseek.com").strip() or "https://api.deepseek.com"
        max_tokens = cls._safe_int_env("AIMC_DEEPSEEK_MAX_TOKENS", default=450, min_value=64, max_value=4096)
        temperature = cls._safe_float_env("AIMC_DEEPSEEK_TEMPERATURE", default=0.2, min_value=0.0, max_value=2.0)

        try:
            transport = DeepSeekTransport(
                api_key=api_key,
                model=model,
                base_url=base_url,
                temperature=temperature,
                max_tokens=max_tokens,
            )
            return cls(timeout_sec=timeout_sec, transport=transport)
        except Exception:
            return cls(timeout_sec=timeout_sec, transport=None)

    @staticmethod
    def _safe_int_env(name: str, *, default: int, min_value: int, max_value: int) -> int:
        raw = os.environ.get(name, "").strip()
        if not raw:
            return default
        try:
            value = int(raw)
        except ValueError:
            return default
        return max(min_value, min(max_value, value))

    @staticmethod
    def _safe_float_env(name: str, *, default: float, min_value: float, max_value: float) -> float:
        raw = os.environ.get(name, "").strip()
        if not raw:
            return default
        try:
            value = float(raw)
        except ValueError:
            return default
        return max(min_value, min(max_value, value))

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
        except Exception:
            card = self._fallback_card(
                scenario=scenario,
                speaker=speaker,
                trigger_reason=trigger_reason,
                source_ts_end=source_ts_end,
            )
            return LLMCallResult(card=card, latency_ms=(time.perf_counter() - started) * 1000, timed_out=False)

    async def _generate_card(self, scenario: str, speaker: str, trigger_reason: str, context: str, source_ts_end: float) -> InsightCard:
        if self.transport is None:
            await asyncio.sleep(0.20)
            return self._heuristic_card(
                scenario=scenario,
                speaker=speaker,
                trigger_reason=trigger_reason,
                context=context,
                source_ts_end=source_ts_end,
            )

        prompt = (
            f"Сценарий: {scenario}\n"
            f"Спикер: {speaker}\n"
            f"Причина триггера: {trigger_reason}\n"
            f"Контекст:\n{context}\n\n"
            "Сформируй короткую карточку помощи."
        )
        payload = await self.transport.generate(prompt=prompt, timeout_sec=self.timeout_sec)
        return self._card_from_payload(
            payload=payload,
            scenario=scenario,
            speaker=speaker,
            trigger_reason=trigger_reason,
            source_ts_end=source_ts_end,
        )

    def _heuristic_card(self, scenario: str, speaker: str, trigger_reason: str, context: str, source_ts_end: float) -> InsightCard:
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

    def _card_from_payload(
        self,
        *,
        payload: dict,
        scenario: str,
        speaker: str,
        trigger_reason: str,
        source_ts_end: float,
    ) -> InsightCard:
        insight = (payload.get("insight") or "").strip()
        reply_cautious = (payload.get("reply_cautious") or "").strip()
        reply_confident = (payload.get("reply_confident") or "").strip()
        resolved_reason = (payload.get("trigger_reason") or "").strip() or trigger_reason
        severity = str(payload.get("severity") or "info").lower().strip()
        if severity not in {"info", "warning", "alert"}:
            severity = "warning"

        if not insight:
            insight = "Ключевой момент обнаружен, зафиксируйте договорённость письменно."
        if not reply_cautious:
            reply_cautious = "Уточним и подтвердим это письменно."
        if not reply_confident:
            reply_confident = "Зафиксируем этот пункт в протоколе прямо сейчас."

        return InsightCard(
            id=str(uuid.uuid4()),
            scenario=scenario,
            card_mode="reply_suggestions",
            trigger_reason=resolved_reason,
            insight=insight[:220],
            reply_cautious=reply_cautious[:220],
            reply_confident=reply_confident[:220],
            severity=severity,
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
