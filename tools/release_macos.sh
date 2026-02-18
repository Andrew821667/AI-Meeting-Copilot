#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Использование: $0 /path/to/AIMeetingCopilot.app"
  exit 1
fi

APP_BUNDLE="$1"
ZIP_PATH="${APP_BUNDLE%.*}.zip"

: "${AIMC_CODESIGN_IDENTITY:?Нужна переменная AIMC_CODESIGN_IDENTITY}"
: "${AIMC_NOTARY_PROFILE:?Нужна переменная AIMC_NOTARY_PROFILE (notarytool keychain profile)}"

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Не найден app bundle: $APP_BUNDLE"
  exit 1
fi

echo "1) Подпись приложения..."
codesign --deep --force --options runtime --sign "$AIMC_CODESIGN_IDENTITY" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "2) Архивация для notarization..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "3) Отправка на notarization..."
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$AIMC_NOTARY_PROFILE" --wait

echo "4) Staple ticket..."
xcrun stapler staple "$APP_BUNDLE"

echo "5) Финальная проверка..."
spctl --assess --verbose "$APP_BUNDLE"

echo "Готово: $APP_BUNDLE подписан и notarized"
