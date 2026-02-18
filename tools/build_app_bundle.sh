#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/dist"
APP_NAME="AIMeetingCopilot"
APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"
WITH_BACKEND=1
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"

usage() {
  cat <<EOF
Использование: $0 [--output-dir <dir>] [--without-backend] [--icon-path <path>]

По умолчанию:
  --output-dir $OUTPUT_DIR
  backend packaging включён
  icon path: $ICON_PATH
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    --without-backend)
      WITH_BACKEND=0
      shift
      ;;
    --icon-path)
      ICON_PATH="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Неизвестный аргумент: $1"
      usage
      exit 1
      ;;
  esac
done

APP_BUNDLE="$OUTPUT_DIR/${APP_NAME}.app"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"

mkdir -p "$OUTPUT_DIR"

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Иконка не найдена: $ICON_PATH"
  echo "Сгенерируй её: ./tools/generate_app_icon.sh \"$ICON_PATH\""
  exit 1
fi

echo "Сборка release binary..."
cd "$ROOT_DIR"
swift build -c release --product "$APP_NAME"

BIN_PATH="$ROOT_DIR/.build/release/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Ошибка: не найден бинарник $BIN_PATH"
  exit 1
fi

echo "Формирование app bundle: $APP_BUNDLE"
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"
chmod +x "$MACOS_DIR/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>
  <string>AI Meeting Copilot</string>
  <key>CFBundleExecutable</key>
  <string>AIMeetingCopilot</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.andrew821667.ai-meeting-copilot</string>
  <key>CFBundleName</key>
  <string>AIMeetingCopilot</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Приложению нужен доступ к микрофону для анализа встречи.</string>
  <key>NSScreenCaptureDescription</key>
  <string>Приложению нужен доступ к записи экрана для захвата аудио собеседника.</string>
</dict>
</plist>
PLIST

cp "$ICON_PATH" "$RESOURCES_DIR/AppIcon.icns"

if [[ "$WITH_BACKEND" -eq 1 ]]; then
  echo "Упаковка backend в app bundle..."
  "$ROOT_DIR/tools/package_backend.sh" "$APP_BUNDLE"
fi

echo "Готово: $APP_BUNDLE"
