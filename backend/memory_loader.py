"""Загрузка пользовательской «памяти» — .md/.txt файлов из папки memory/.

Текущая реализация (Plain): склеиваем содержимое всех файлов в system prompt
LLM с защитой от prompt injection. RAG-режим (chunking + embeddings) —
плейсхолдер: настройки сохраняются, но индексация ещё не реализована.

Когда папка вырастет за ~7000 токенов суммарно — пора будет переходить на
embeddings + retrieval.
"""

from __future__ import annotations

import json
import logging
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

logger = logging.getLogger("aimc.backend.memory")

SUPPORTED_SUFFIXES = {".md", ".txt", ".markdown"}
DEFAULT_MAX_CHARS = 30_000  # ~7500 токенов, безопасно для DeepSeek
SETTINGS_FILENAME = "memory_settings.json"

VALID_MODES = ("plain", "rag")

README_TEMPLATE = """# Память для AI Meeting Copilot

Положи сюда `.md` или `.txt` файлы — приложение прочитает их перед каждым
ответом и будет учитывать как фоновый контекст.

Что сюда класть:
- факты о тебе, твоей компании, продукте, проекте;
- определения и термины, которые часто всплывают на встречах;
- список открытых вопросов, KPI, договорённостей;
- что-нибудь, что ты повторяешь собеседникам каждый раз.

Чего сюда НЕ класть:
- транскрипты прошлых встреч (они и так сохраняются автоматически);
- очень большие документы (>5–10 страниц): в Plain-режиме весь корпус
  склеивается целиком, лимит ~7500 токенов. В RAG-режиме (когда будет
  включён) — без жёсткого лимита.

Как обновлять:
- редактируй файлы и нажимай «Обновить» в окне «Память».
"""


@dataclass(frozen=True)
class MemoryFile:
    path: Path
    content: str


@dataclass
class MemorySettings:
    enabled: bool = True
    mode: str = "plain"  # plain | rag

    def normalized(self) -> "MemorySettings":
        mode = self.mode if self.mode in VALID_MODES else "plain"
        return MemorySettings(enabled=bool(self.enabled), mode=mode)


@dataclass
class MemoryFileInfo:
    name: str
    size_bytes: int
    chars: int
    modified_ts: float


@dataclass
class MemoryState:
    settings: MemorySettings
    files: list[MemoryFileInfo] = field(default_factory=list)
    total_chars: int = 0
    limit_chars: int = DEFAULT_MAX_CHARS
    truncated: bool = False
    folder_path: str = ""
    rag_available: bool = False  # пока всегда False — фича в разработке

    def to_dict(self) -> dict[str, Any]:
        return {
            "settings": asdict(self.settings),
            "files": [asdict(f) for f in self.files],
            "total_chars": self.total_chars,
            "limit_chars": self.limit_chars,
            "truncated": self.truncated,
            "folder_path": self.folder_path,
            "rag_available": self.rag_available,
        }


def memory_dir() -> Path:
    return Path.home() / "Library/Application Support/AIMeetingCopilot/memory"


def settings_path() -> Path:
    return memory_dir().parent / SETTINGS_FILENAME


def ensure_memory_dir(path: Path | None = None) -> Path:
    """Создаёт папку памяти при первом обращении и кладёт README, если пусто."""
    target = path or memory_dir()
    target.mkdir(parents=True, exist_ok=True)
    readme = target / "README.md"
    if not readme.exists() and not any(target.iterdir()):
        readme.write_text(README_TEMPLATE, encoding="utf-8")
    return target


def load_settings(path: Path | None = None) -> MemorySettings:
    target = path or settings_path()
    if not target.exists():
        return MemorySettings()
    try:
        raw = json.loads(target.read_text(encoding="utf-8"))
        return MemorySettings(
            enabled=bool(raw.get("enabled", True)),
            mode=str(raw.get("mode", "plain")),
        ).normalized()
    except Exception:
        logger.exception("memory: failed to load settings, using defaults")
        return MemorySettings()


def save_settings(settings: MemorySettings, path: Path | None = None) -> None:
    target = path or settings_path()
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(asdict(settings.normalized()), ensure_ascii=False, indent=2), encoding="utf-8")


def _read_file(path: Path) -> str | None:
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        try:
            return path.read_text(encoding="cp1251")
        except Exception:
            logger.warning("memory: skipping unreadable %s", path.name)
            return None
    except OSError as exc:
        logger.warning("memory: cannot read %s: %s", path.name, exc)
        return None


def load_memory_files(path: Path | None = None) -> list[MemoryFile]:
    target = path or memory_dir()
    if not target.exists():
        return []
    files: list[MemoryFile] = []
    for entry in sorted(target.iterdir()):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            continue
        if entry.suffix.lower() not in SUPPORTED_SUFFIXES:
            continue
        if entry.name == "README.md":
            continue
        content = _read_file(entry)
        if not content or not content.strip():
            continue
        files.append(MemoryFile(path=entry, content=content.strip()))
    return files


def list_memory_files_meta(path: Path | None = None) -> list[MemoryFileInfo]:
    target = path or memory_dir()
    if not target.exists():
        return []
    out: list[MemoryFileInfo] = []
    for entry in sorted(target.iterdir()):
        if entry.name.startswith("."):
            continue
        if entry.is_dir():
            continue
        if entry.suffix.lower() not in SUPPORTED_SUFFIXES:
            continue
        if entry.name == "README.md":
            continue
        try:
            stat = entry.stat()
            content = _read_file(entry) or ""
            out.append(MemoryFileInfo(
                name=entry.name,
                size_bytes=stat.st_size,
                chars=len(content),
                modified_ts=stat.st_mtime,
            ))
        except OSError:
            continue
    return out


def build_memory_block(
    path: Path | None = None,
    max_chars: int = DEFAULT_MAX_CHARS,
    settings: MemorySettings | None = None,
) -> str:
    """Возвращает готовый текст памяти для вклейки в system prompt, либо ''."""
    cfg = (settings or load_settings()).normalized()
    if not cfg.enabled:
        return ""
    if cfg.mode == "rag":
        # RAG ещё не реализован — fallback на plain, чтобы фича работала.
        logger.info("memory: RAG mode requested but not implemented, falling back to plain")

    files = load_memory_files(path)
    if not files:
        return ""

    parts: list[str] = []
    used = 0
    truncated = False
    for memfile in files:
        header = f"### {memfile.path.name}"
        block = f"{header}\n{memfile.content}"
        if used + len(block) + 2 > max_chars:
            remaining = max_chars - used - len(header) - 4
            if remaining > 200:
                parts.append(f"{header}\n{memfile.content[:remaining]}\n[...обрезано]")
                used = max_chars
            truncated = True
            break
        parts.append(block)
        used += len(block) + 2

    body = "\n\n".join(parts)
    suffix = "\n\n[...память обрезана по лимиту, разнеси на несколько файлов]" if truncated else ""
    logger.info(
        "memory: loaded %d files, %d chars used (limit %d)%s",
        len(files), used, max_chars, " [TRUNCATED]" if truncated else "",
    )
    return body + suffix


def collect_state(
    path: Path | None = None,
    max_chars: int = DEFAULT_MAX_CHARS,
    settings: MemorySettings | None = None,
) -> MemoryState:
    cfg = (settings or load_settings()).normalized()
    target = path or memory_dir()
    files_meta = list_memory_files_meta(target)
    total = sum(f.chars for f in files_meta)
    return MemoryState(
        settings=cfg,
        files=files_meta,
        total_chars=total,
        limit_chars=max_chars,
        truncated=total > max_chars,
        folder_path=str(target),
        rag_available=False,
    )
