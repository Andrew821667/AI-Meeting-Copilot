# Production Readiness Checklist

## 1. Release Gate (обязательно перед релизом)

- `PYTHONPATH=backend pytest -q backend/tests` завершился без ошибок.
- Прогон `swift test` на чистой машине с актуальным Xcode завершился без ошибок.
- Прогнан 60-90 минутный стресс-тест (`backend/tests/stress_test.py`) и сохранён отчёт.
- Пройден healthcheck backend: `python3 backend/main.py --healthcheck`.
- Пройден UDS smoke-тест: `./tools/smoke_test_backend.sh`.
- Проверен fallback сценарий LLM: при таймауте появляется fallback-карточка.
- Проверен fallback сценарий аудио: при отсутствии сигнала SCK включается BlackHole режим.

## 2. Toolchain и окружение

- macOS 14+.
- Xcode и Command Line Tools одной версии (без mismatch SDK/Swift compiler).
- Python 3.11 для CI и backend-инструментов.
- Все Python-зависимости установлены из `/Users/andrew/Мои AI проекты/AI-Meeting-Copilot/requirements.txt`.

## 3. Секреты и безопасность

- DeepSeek API ключ хранится в macOS Keychain (production).
- Для dev/staging допускается переменная окружения `AIMC_DEEPSEEK_API_KEY`.
- Логи не содержат API ключи и PII.
- Экспорт сессий хранится в ограниченном каталоге с правами доступа только для пользователя.

## 4. Наблюдаемость

- Включён сбор telemetry метрик (таймауты, latency, pending queue, degraded mode).
- Проверено, что JSON-экспорт содержит `metrics`, `settings`, `meeting_memory`.
- Runtime предупреждения о высокой LLM latency выводятся в UI.

## 5. Релизный контур

- Сформирован `.app` bundle.
- Выполнен packaging backend: `/Users/andrew/Мои AI проекты/AI-Meeting-Copilot/tools/package_backend.sh`.
- Выполнены подпись и notarization:
  - `/Users/andrew/Мои AI проекты/AI-Meeting-Copilot/tools/release_macos.sh`
  - `/Users/andrew/Мои AI проекты/AI-Meeting-Copilot/docs/ops/release-macos.md`
- Проверено, что backend запускается из `App.app/Contents/Resources/backend`.
- Прогнан smoke-тест: старт сессии -> получение карточки -> end сессии -> экспорт отчёта.

## 6. Known Gaps (для "полной" production версии)

- Подпись приложения и notarization через Apple Developer.
- Авто-обновления (Sparkle или эквивалент).
- Централизованный crash-reporting (Sentry/Crashlytics/self-hosted).
- E2E тесты UI поверх Zoom/Meet в CI невозможны без отдельного device lab.
