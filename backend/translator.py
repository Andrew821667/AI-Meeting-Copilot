"""Локальный переводчик на NLLB-200-distilled-1.3B через CTranslate2.

Полностью офлайн: модель лежит в Application Support, ничего не уходит в
сеть. Перевод короткой фразы на Apple Silicon (int8) — 0.2–0.5 сек.

Направление определяется автоматически по доле кириллицы:
ru → en / en → ru.
"""

from __future__ import annotations

import logging
import os
import threading
from pathlib import Path

logger = logging.getLogger("aimc.backend.translator")

DEFAULT_MODEL_DIR = (
    Path.home()
    / "Library/Application Support/AIMeetingCopilot/models/nllb-200-distilled-1.3B-ct2"
)
HF_TOKENIZER_ID = "facebook/nllb-200-distilled-1.3B"

RU = "rus_Cyrl"
EN = "eng_Latn"


def model_dir() -> Path:
    explicit = os.environ.get("AIMC_NLLB_MODEL_DIR", "").strip()
    return Path(explicit).expanduser() if explicit else DEFAULT_MODEL_DIR


def model_available() -> bool:
    return (model_dir() / "model.bin").exists()


def detect_lang(text: str) -> str:
    """ru/en по доле кириллицы — для пары ru↔en этого достаточно."""
    cyr = sum(1 for ch in text if "Ѐ" <= ch <= "ӿ")
    letters = sum(1 for ch in text if ch.isalpha())
    if letters == 0:
        return "en"
    return "ru" if cyr / letters > 0.3 else "en"


class LocalTranslator:
    """Ленивая загрузка модели: первая фраза платит ~2-5с за инициализацию,
    дальше перевод занимает сотни миллисекунд. Потокобезопасен."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._translator = None
        self._tokenizer = None
        self._load_failed = False

    @property
    def ready(self) -> bool:
        return self._translator is not None

    def _ensure_loaded(self) -> bool:
        if self._translator is not None:
            return True
        if self._load_failed:
            return False
        with self._lock:
            if self._translator is not None:
                return True
            if self._load_failed:
                return False
            if not model_available():
                logger.warning(
                    "translator: model not found at %s — run tools/setup_translator.sh",
                    model_dir(),
                )
                self._load_failed = True
                return False
            try:
                import ctranslate2
                from transformers import AutoTokenizer

                logger.info("translator: loading NLLB from %s", model_dir())
                self._translator = ctranslate2.Translator(
                    str(model_dir()),
                    device="cpu",
                    compute_type="int8",
                    inter_threads=1,
                    intra_threads=4,
                )
                # Токенизатор лежит рядом с моделью (готовый CT2-репозиторий
                # включает tokenizer.json) — грузим локально, чтобы не ходить
                # в сеть. Fallback на HF-id для старых установок без токенизатора.
                tok_source = (
                    str(model_dir())
                    if (model_dir() / "tokenizer.json").exists()
                    else HF_TOKENIZER_ID
                )
                self._tokenizer = AutoTokenizer.from_pretrained(tok_source)
                logger.info("translator: NLLB ready")
                return True
            except Exception:
                logger.exception("translator: failed to load model")
                self._load_failed = True
                self._translator = None
                self._tokenizer = None
                return False

    def translate(self, text: str) -> tuple[str, str, str] | None:
        """Возвращает (перевод, src_lang, tgt_lang) или None при ошибке."""
        stripped = text.strip()
        if not stripped:
            return None
        if not self._ensure_loaded():
            return None

        src = detect_lang(stripped)
        src_code, tgt_code = (RU, EN) if src == "ru" else (EN, RU)
        try:
            self._tokenizer.src_lang = src_code
            tokens = self._tokenizer.convert_ids_to_tokens(
                self._tokenizer.encode(stripped)
            )
            results = self._translator.translate_batch(
                [tokens],
                target_prefix=[[tgt_code]],
                beam_size=2,
                max_decoding_length=256,
            )
            out_tokens = results[0].hypotheses[0]
            if out_tokens and out_tokens[0] == tgt_code:
                out_tokens = out_tokens[1:]
            translated = self._tokenizer.decode(
                self._tokenizer.convert_tokens_to_ids(out_tokens),
                skip_special_tokens=True,
            ).strip()
            if not translated:
                return None
            return (translated, src, "en" if src == "ru" else "ru")
        except Exception:
            logger.exception("translator: translation failed")
            return None
