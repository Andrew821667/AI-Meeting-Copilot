# macOS Release (Signing + Notarization)

## Требования

- Apple Developer ID Application сертификат в keychain.
- Нотаризация: либо `notarytool` profile, либо App Store Connect API key.
- Собранный `.app` bundle.

## Переменные окружения

```bash
export AIMC_CODESIGN_IDENTITY="Developer ID Application: Company Name (TEAMID)"
export AIMC_NOTARY_PROFILE="aimc-notary-profile"
```

Альтернатива для CI/API key режима:

```bash
export AIMC_CODESIGN_IDENTITY="Developer ID Application: Company Name (TEAMID)"
export AIMC_NOTARY_KEY_ID="XXXXXXXXXX"
export AIMC_NOTARY_ISSUER_ID="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export AIMC_NOTARY_KEY_PATH="/absolute/path/AuthKey_XXXXXXXXXX.p8"
```

## Шаги

```bash
cd "/Users/andrew/Мои AI проекты/AI-Meeting-Copilot"
./tools/release_preflight.sh
./tools/build_app_bundle.sh --output-dir dist
./tools/release_macos.sh "/path/to/AIMeetingCopilot.app"
```

Скрипт выполняет:
1. `codesign --deep --options runtime`
2. `notarytool submit --wait`
3. `stapler staple`
4. `spctl --assess`
