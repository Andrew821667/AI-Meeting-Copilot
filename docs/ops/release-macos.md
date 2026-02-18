# macOS Release (Signing + Notarization)

## Требования

- Apple Developer ID Application сертификат в keychain.
- Настроенный `notarytool` keychain profile.
- Собранный `.app` bundle.

## Переменные окружения

```bash
export AIMC_CODESIGN_IDENTITY="Developer ID Application: Company Name (TEAMID)"
export AIMC_NOTARY_PROFILE="aimc-notary-profile"
```

## Шаги

```bash
cd "/Users/andrew/Мои AI проекты/AI-Meeting-Copilot"
./tools/release_macos.sh "/path/to/AIMeetingCopilot.app"
```

Скрипт выполняет:
1. `codesign --deep --options runtime`
2. `notarytool submit --wait`
3. `stapler staple`
4. `spctl --assess`
