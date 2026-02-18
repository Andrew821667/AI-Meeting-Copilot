# Stage 23 Report - Runtime & Release Hardening

Дата: 2026-02-18

## Что сделано

- Усилен runtime backend (`backend/main.py`):
  - структурированное логирование;
  - `--healthcheck` режим;
  - защита от некорректных входных пакетов (JSON/envelope/payload);
  - безопасная обработка неизвестных типов событий;
  - graceful shutdown по `SIGINT/SIGTERM` с очисткой UDS-файла.
- Добавлены тесты runtime:
  - `backend/tests/test_main_runtime.py`.
- Добавлен UDS smoke-тест:
  - `tools/smoke_test_backend.sh`.
- Добавлен релизный скрипт подписания/notarization:
  - `tools/release_macos.sh`.
- Добавлен runbook релиза:
  - `docs/ops/release-macos.md`.
- Расширен CI:
  - healthcheck backend;
  - UDS smoke test.

## Проверки

- `PYTHONPATH=backend pytest -q backend/tests` -> 36 passed.
- `python3 backend/main.py --healthcheck --exports-dir /tmp/aimc-healthcheck-test` -> OK.
- `./tools/smoke_test_backend.sh` -> OK.

## Остаточные внешние задачи

- Настроить production-секреты для `notarytool` profile и codesign identity на релизной машине.
- Выполнить финальную подпись/notarization реального `.app` перед дистрибуцией.
