#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Использование: $0 /path/to/AIMeetingCopilot.app"
  exit 1
fi

APP_BUNDLE="$1"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
TARGET_DIR="$RESOURCES_DIR/backend"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Ошибка: app bundle не найден: $APP_BUNDLE"
  exit 1
fi

mkdir -p "$TARGET_DIR"

if command -v pyinstaller >/dev/null 2>&1; then
  BUILD_DIR="$(mktemp -d)"
  pushd "$BACKEND_DIR" >/dev/null
  pyinstaller --noconfirm --onefile main.py --name backend_runner --distpath "$BUILD_DIR/dist" --workpath "$BUILD_DIR/build"
  popd >/dev/null

  cp "$BUILD_DIR/dist/backend_runner" "$TARGET_DIR/backend_runner"
  chmod +x "$TARGET_DIR/backend_runner"
  rm -rf "$BUILD_DIR"
  echo "Готово: backend_runner -> $TARGET_DIR/backend_runner"
else
  echo "pyinstaller не найден, копирую python backend как fallback."
  rsync -a --exclude '.venv' --exclude '__pycache__' --exclude '.pytest_cache' "$BACKEND_DIR/" "$TARGET_DIR/"
  cp "$ROOT_DIR/requirements.txt" "$RESOURCES_DIR/requirements.txt"
  echo "Готово: backend scripts -> $TARGET_DIR"
  echo "Готово: requirements.txt -> $RESOURCES_DIR/requirements.txt"
fi
