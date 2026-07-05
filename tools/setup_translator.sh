#!/usr/bin/env bash
# Ставит локальный переводчик NLLB-200-distilled-1.3B (CTranslate2 int8).
#
# Скачивает УЖЕ сконвертированную CT2-модель с HuggingFace — без torch и без
# шага конвертации. Одноразово, ~1.4GB на диск. Токенизатор идёт в комплекте,
# поэтому после установки перевод работает полностью офлайн.
set -euo pipefail

MODEL_REPO="${AIMC_NLLB_REPO:-OpenNMT/nllb-200-distilled-1.3B-ct2-int8}"
MODEL_DIR="${AIMC_NLLB_MODEL_DIR:-$HOME/Library/Application Support/AIMeetingCopilot/models/nllb-200-distilled-1.3B-ct2}"
PYTHON="${AIMC_PYTHON:-$(dirname "$0")/../backend/.venv/bin/python3}"

if [ -f "$MODEL_DIR/model.bin" ]; then
  echo "Модель уже установлена: $MODEL_DIR"
  exit 0
fi

if [ ! -x "$PYTHON" ]; then
  echo "Не найден Python venv: $PYTHON" >&2
  echo "Укажи путь через AIMC_PYTHON=/path/to/python3" >&2
  exit 1
fi

echo "Проверяю зависимости переводчика (ctranslate2, transformers, sentencepiece)…"
if ! "$PYTHON" -c "import ctranslate2, transformers, sentencepiece, huggingface_hub" 2>/dev/null; then
  echo "Ставлю недостающие зависимости…"
  "$PYTHON" -m pip install -q "ctranslate2>=4.6.1" "transformers>=4.46" sentencepiece "huggingface_hub>=0.24"
fi

echo "Скачиваю $MODEL_REPO -> $MODEL_DIR"
mkdir -p "$MODEL_DIR"

AIMC_NLLB_REPO="$MODEL_REPO" AIMC_NLLB_MODEL_DIR="$MODEL_DIR" "$PYTHON" - <<'PY'
import os
from huggingface_hub import snapshot_download

repo = os.environ["AIMC_NLLB_REPO"]
dest = os.environ["AIMC_NLLB_MODEL_DIR"]
snapshot_download(
    repo_id=repo,
    local_dir=dest,
    allow_patterns=[
        "model.bin", "config.json", "generation_config.json",
        "shared_vocabulary.*", "tokenizer.json", "tokenizer_config.json",
        "special_tokens_map.json", "sentencepiece.bpe.model",
    ],
)
print("Скачано в:", dest)
PY

echo "Готово: $MODEL_DIR"
