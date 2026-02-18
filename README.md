# AI-Meeting-Copilot

macOS-приложение для realtime-подсказок на онлайн-встречах.

## Текущий статус

- Закрыты этапы 0-22 дорожной карты.
- Внедрены fallback-механизмы для LLM и аудио.
- Подключён CI для Python и Swift тестов.
- Добавлен production-checklist: `/Users/andrew/Мои AI проекты/AI-Meeting-Copilot/docs/ops/production-readiness.md`.

## Быстрый запуск backend (dev)

```bash
cd "/Users/andrew/Мои AI проекты/AI-Meeting-Copilot"
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=backend pytest -q backend/tests
python3 backend/main.py --socket /tmp/aimc.sock --exports-dir exports
```

Переменные окружения для DeepSeek:
- `/Users/andrew/Мои AI проекты/AI-Meeting-Copilot/backend/.env.example`

## Stage artifacts
- docs/architecture/realtime-boundary.md
- docs/contracts/event-contract.md
- docs/contracts/events.schema.json
- docs/telemetry/slo-and-metrics.md
- docs/process/mvp-definition-of-done.md
- docs/process/stage-gates.md
- docs/process/stage-1-report.md
- docs/process/stage-2-report.md
- docs/process/stage-3-report.md
- docs/process/stage-4-report.md
- docs/process/stage-5-report.md
- docs/process/stage-6-report.md
- docs/process/stage-7-report.md
- docs/process/stage-8-report.md
- docs/process/stage-9-report.md
- docs/process/stage-10-report.md
- docs/process/stage-11-report.md
- docs/process/stage-12-report.md
- docs/process/stage-13-report.md
- docs/process/stage-14-report.md
- docs/process/stage-15-report.md
- docs/process/stage-16-report.md
- docs/process/stage-17-report.md
- docs/process/stage-18-report.md
- docs/process/stage-19-report.md
- docs/process/stage-20-report.md
- docs/process/stage-21-report.md
- docs/process/stage-22-report.md
