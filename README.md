# AI-Meeting-Copilot

![Status](https://img.shields.io/badge/status-beta-yellow)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Python](https://img.shields.io/badge/Python-3.11-blue)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## Что это такое

AI Meeting Copilot — нативное macOS-приложение, которое в фоне слушает онлайн-встречу и помогает пользователю короткими подсказками в реальном времени. Оно использует DeepSeek LLM для рекомендаций по ответам и анализу контекста, а также определяет, кто говорит, через diarization на базе Resemblyzer.

## Demo

> Скриншоты будут добавлены перед публичным релизом

## Требования

- macOS 13 Ventura и выше
- Apple Silicon или Intel Mac
- DeepSeek API key

## Текущий статус

- Закрыты этапы 0-25 дорожной карты.
- Внедрены fallback-механизмы для LLM и аудио.
- Подключён CI для Python и Swift тестов.
- Добавлены healthcheck и UDS smoke-тест backend.
- Добавлены релизные скрипты подписи/notarization macOS.
- Production-checklist: `./docs/ops/production-readiness.md`.

## Быстрый запуск backend (dev)

```bash
cd .
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=backend pytest -q backend/tests
python3 backend/main.py --socket /tmp/aimc.sock --exports-dir exports
```

Переменные окружения для DeepSeek:
- `./backend/.env.example`

Локально (рекомендуется, без git):
```bash
mkdir -p "$HOME/Library/Application Support/AIMeetingCopilot"
cat > "$HOME/Library/Application Support/AIMeetingCopilot/.env" <<'EOF'
AIMC_DEEPSEEK_API_KEY=your_deepseek_key_here
AIMC_DEEPSEEK_MODEL=deepseek-chat
EOF
```

Операционные инструменты:
- `./tools/smoke_test_backend.sh`
- `./tools/build_app_bundle.sh`
- `./tools/release_preflight.sh`
- `./tools/release_macos.sh`

## Roadmap

- [x] Этапы 0–25: ASR, speaker diarization, LLM, CI/CD, нотаризация macOS
- [ ] Финальное тестирование и стабилизация
- [ ] Публичный релиз v1.0

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
- docs/process/stage-23-report.md
- docs/process/stage-24-report.md
- docs/process/stage-25-report.md
