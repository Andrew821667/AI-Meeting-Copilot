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

## Статус проекта

Проект находится на стадии публичной beta / финального тестирования. Приложение уже работает локально, но мы всё ещё стабилизируем UX, поведение realtime-карточек, обработку macOS permissions и сценарии захвата/анализа аудио.

Если вы хотите помочь, сейчас особенно полезны:
- тесты на разных версиях macOS и разных типах Mac;
- отчёты о сбоях, зависаниях и неверном поведении интерфейса;
- UX-обратная связь по карточкам, транскрипции и потокам подсказок;
- предложения и pull request'ы по стабильности, документации и девелоперскому опыту.

## Известные ограничения

- Проект ещё не заявлен как production-ready.
- Некоторые realtime-сценарии и режимы карточек находятся в активной доработке.
- Поведение системных разрешений macOS и захвата аудио может отличаться на разных конфигурациях.
- Интерфейс и внутренняя логика продолжают стабилизироваться по итогам beta-тестирования.

## Как помочь

- Откройте `Issue`, если нашли баг, нестабильность или странное поведение.
- Если берёте задачу в работу, напишите об этом в issue перед началом, чтобы не дублировать усилия.
- Для небольших улучшений подойдут задачи с метками `good first issue` и `help wanted`.
- Если тестируете локально, прикладывайте версию macOS, тип Mac, режим приложения и шаги воспроизведения.
- Подробные правила совместной работы: `./CONTRIBUTING.md`.

Production-checklist: `./docs/ops/production-readiness.md`.

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
cat > "$HOME/Library/Application Support/AIMeetingCopilot/.env" <<'EOF_ENV'
AIMC_DEEPSEEK_API_KEY=your_deepseek_key_here
AIMC_DEEPSEEK_MODEL=deepseek-chat
EOF_ENV
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

## Для будущего публичного релиза

Перед переводом репозитория в `public` желательно:
- убедиться, что в репозитории нет секретов и локальных артефактов;
- собрать и проверить релизный `.dmg`;
- обновить changelog для `v1.0.0-beta`;
- завести стартовые issues для beta-тестирования и первых контрибьюторов.

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
