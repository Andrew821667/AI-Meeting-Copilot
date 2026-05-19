"""Тонкий клиент к OpenClaw Memory Hub (https://memory.ai-verdict.ru).

Endpoints, на которые мы опираемся (OpenAPI v0.3.0):
- GET  /health        — liveness probe
- GET  /context/build — готовый RAG-блок под запрос (используем для system prompt)
- POST /capture       — записать встречу как новый источник памяти

Auth: Bearer токен из env AIMC_MEMORYHUB_TOKEN. URL берётся из
AIMC_MEMORYHUB_URL (default https://memory.ai-verdict.ru). Если токен
или URL не заданы — клиент возвращается в disabled-режим (все методы
тихо отдают пустой результат, чтобы не валить сессию).
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any

import httpx

logger = logging.getLogger("aimc.backend.memory_hub")

DEFAULT_URL = "https://memory.ai-verdict.ru"
TIMEOUT_CONTEXT_SEC = 15.0  # /context/build делает hybrid search + summary
                            # через OpenAI; на пустом/холодном корпусе может
                            # подвисать на 10-15с. Дольше держать не имеет
                            # смысла — иначе сам ответ Copilot будет тормозить.
TIMEOUT_CAPTURE_SEC = 20.0  # capture тригерит пайплайн извлечения memory_items


@dataclass
class MemoryHubConfig:
    base_url: str
    token: str

    @property
    def enabled(self) -> bool:
        return bool(self.base_url and self.token)

    @classmethod
    def from_env(cls) -> "MemoryHubConfig":
        base = os.environ.get("AIMC_MEMORYHUB_URL", DEFAULT_URL).rstrip("/")
        token = os.environ.get("AIMC_MEMORYHUB_TOKEN", "").strip()
        return cls(base_url=base, token=token)


class MemoryHubClient:
    def __init__(self, config: MemoryHubConfig | None = None) -> None:
        self.config = config or MemoryHubConfig.from_env()

    def _auth_headers(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.config.token}"}

    def ping(self) -> bool:
        if not self.config.enabled:
            return False
        try:
            r = httpx.get(f"{self.config.base_url}/health", timeout=3.0)
            return r.status_code == 200
        except Exception:
            return False

    def build_context(
        self,
        query: str,
        *,
        max_items: int = 8,
        max_tokens: int = 1500,
        scope: str | None = None,
        project: str | None = None,
    ) -> str:
        """Возвращает готовый RAG-блок для system prompt или '' при любой ошибке."""
        if not self.config.enabled:
            return ""
        q = (query or "").strip()
        if not q:
            return ""

        params: dict[str, Any] = {
            "query": q,
            "max_tokens": max_tokens,
            "retrieve_k": max_items,
            "summary": True,
        }
        if scope:
            params["scope"] = scope
        if project:
            params["project"] = project

        try:
            r = httpx.get(
                f"{self.config.base_url}/context/build",
                params=params,
                headers=self._auth_headers(),
                timeout=TIMEOUT_CONTEXT_SEC,
            )
        except httpx.TimeoutException:
            logger.warning(
                "memory_hub: /context/build timed out after %.0fs (Hub slow/empty?)",
                TIMEOUT_CONTEXT_SEC,
            )
            return ""
        except Exception as exc:
            logger.warning("memory_hub: context build failed: %s", exc)
            return ""

        if r.status_code != 200:
            logger.warning("memory_hub: context build %s: %s", r.status_code, r.text[:200])
            return ""

        try:
            payload = r.json()
        except Exception:
            return r.text

        # Hub может вернуть либо строку (готовый контекст), либо объект с
        # полем "context"/"text"/"content" — берём наиболее вероятное.
        if isinstance(payload, str):
            return payload
        if isinstance(payload, dict):
            for key in ("context", "text", "content", "summary"):
                v = payload.get(key)
                if isinstance(v, str) and v.strip():
                    return v
            # Fallback: items[].text/.content
            items = payload.get("items") or payload.get("memory_items") or []
            chunks: list[str] = []
            for item in items:
                if isinstance(item, dict):
                    txt = item.get("text") or item.get("content") or ""
                    if txt:
                        chunks.append(str(txt).strip())
            if chunks:
                return "\n\n────────\n\n".join(chunks)
        return ""

    def capture_session(
        self,
        *,
        session_id: str,
        title: str,
        content: str,
        duration_sec: float,
        participants_count: int = 0,
        profile_id: str = "",
    ) -> bool:
        """Шлёт POST /capture с транскриптом и карточками. external_id=session_id
        обеспечивает идемпотентность — повторный вызов с тем же id не задвоит.
        """
        if not self.config.enabled:
            return False
        if not content.strip():
            return False

        body = {
            "source": "meeting_copilot",
            "source_type": "meeting",
            "external_id": session_id,
            "title": title,
            "content": content,
            "metadata": {
                "session_id": session_id,
                "duration_sec": int(duration_sec),
                "participants_count": participants_count,
                "captured_at": datetime.now(timezone.utc).isoformat(),
                "profile_id": profile_id,
            },
        }

        try:
            r = httpx.post(
                f"{self.config.base_url}/capture",
                json=body,
                headers=self._auth_headers(),
                timeout=TIMEOUT_CAPTURE_SEC,
            )
        except Exception as exc:
            logger.warning("memory_hub: capture failed: %s", exc)
            return False

        if 200 <= r.status_code < 300:
            logger.info("memory_hub: captured session %s (%d chars)", session_id, len(content))
            return True
        logger.warning("memory_hub: capture %s: %s", r.status_code, r.text[:200])
        return False
