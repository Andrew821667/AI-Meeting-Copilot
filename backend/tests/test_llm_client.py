import asyncio
import os

from llm_client import DeepSeekTransport, LLMTransport, RealtimeLLMClient


class FakeTransport(LLMTransport):
    def __init__(self, payload: dict) -> None:
        self.payload = payload

    async def generate(self, *, prompt: str, timeout_sec: float) -> dict:
        return self.payload


class SlowTransport(LLMTransport):
    def __init__(self, delay_sec: float = 0.2) -> None:
        self.delay_sec = delay_sec

    async def generate(self, *, prompt: str, timeout_sec: float) -> dict:
        await asyncio.sleep(self.delay_sec)
        return {"insight": "slow"}


def test_llm_client_uses_transport_payload() -> None:
    client = RealtimeLLMClient(
        timeout_sec=1.0,
        transport=FakeTransport(
            {
                "insight": "Нужно подтвердить SLA письменно",
                "reply_cautious": "Уточним детали и зафиксируем их.",
                "reply_confident": "Фиксируем SLA в протоколе прямо сейчас.",
                "trigger_reason": "SLA и дедлайн обсуждаются",
                "severity": "warning",
            }
        ),
    )

    result = asyncio.run(
        client.build_card(
            scenario="negotiation",
            speaker="THEM",
            trigger_reason="raw",
            context="THEM: SLA и дедлайн",
            source_ts_end=1.0,
        )
    )
    assert result.card.is_fallback is False
    assert "SLA" in result.card.insight
    assert result.card.severity == "warning"


def test_llm_client_falls_back_on_timeout() -> None:
    client = RealtimeLLMClient(timeout_sec=0.05, transport=SlowTransport(delay_sec=0.2))
    result = asyncio.run(
        client.build_card(
            scenario="negotiation",
            speaker="THEM",
            trigger_reason="trigger",
            context="THEM: дедлайн",
            source_ts_end=1.0,
        )
    )
    assert result.timed_out is True
    assert result.card.is_fallback is True


def test_llm_client_normalizes_invalid_severity() -> None:
    client = RealtimeLLMClient(timeout_sec=1.0, transport=FakeTransport({"insight": "x", "severity": "critical"}))
    result = asyncio.run(
        client.build_card(
            scenario="negotiation",
            speaker="THEM",
            trigger_reason="trigger",
            context="THEM: дедлайн",
            source_ts_end=1.0,
        )
    )
    assert result.card.severity == "warning"


def test_llm_client_local_mode_without_key() -> None:
    original = os.environ.pop("AIMC_DEEPSEEK_API_KEY", None)
    try:
        client = RealtimeLLMClient.from_env(timeout_sec=1.0)
        result = asyncio.run(
            client.build_card(
                scenario="negotiation",
                speaker="THEM",
                trigger_reason="trigger",
                context="THEM: дедлайн и штраф",
                source_ts_end=1.0,
            )
        )
        assert result.card.is_fallback is False
        assert result.card.insight != ""
    finally:
        if original is not None:
            os.environ["AIMC_DEEPSEEK_API_KEY"] = original


def test_extract_json_text_from_code_fence() -> None:
    payload = "```json\n{\"insight\":\"ok\"}\n```"
    extracted = DeepSeekTransport._extract_json_text(payload)
    assert extracted == "{\"insight\":\"ok\"}"


def test_env_parsing_is_safe_for_invalid_values() -> None:
    original = {
        "AIMC_DEEPSEEK_API_KEY": os.environ.get("AIMC_DEEPSEEK_API_KEY"),
        "AIMC_DEEPSEEK_MAX_TOKENS": os.environ.get("AIMC_DEEPSEEK_MAX_TOKENS"),
        "AIMC_DEEPSEEK_TEMPERATURE": os.environ.get("AIMC_DEEPSEEK_TEMPERATURE"),
    }
    try:
        os.environ["AIMC_DEEPSEEK_API_KEY"] = "test-key"
        os.environ["AIMC_DEEPSEEK_MAX_TOKENS"] = "NaN"
        os.environ["AIMC_DEEPSEEK_TEMPERATURE"] = "bad"
        client = RealtimeLLMClient.from_env(timeout_sec=1.0)
        result = asyncio.run(
            client.build_card(
                scenario="negotiation",
                speaker="THEM",
                trigger_reason="trigger",
                context="THEM: дедлайн",
                source_ts_end=1.0,
            )
        )
        assert result.card.insight != ""
    finally:
        for key, value in original.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
