# AI-Meeting-Copilot

![Status](https://img.shields.io/badge/status-beta-yellow)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![Python](https://img.shields.io/badge/Python-3.11-blue)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)

## Русский

### Что это

AI Meeting Copilot — это macOS-приложение для встреч и разговоров.
Оно слушает речь, показывает живую транскрипцию и подсказывает варианты ответа с помощью DeepSeek.

Проще говоря: вы разговариваете, а приложение помогает не терять контекст и быстрее реагировать по ходу встречи.

### Почему это может быть полезно

- помогает не терять важные детали разговора;
- даёт быстрые подсказки прямо по ходу встречи;
- снижает нагрузку, когда нужно одновременно слушать, думать и отвечать.

### Для кого

Приложение может быть полезно, если вы:
- проходите собеседования;
- проводите переговоры;
- ведёте консультации;
- участвуете в рабочих созвонах;
- хотите разбирать офлайн-разговор через микрофон.

### Статус проекта

Проект находится на стадии `public beta` / финального тестирования.

Это значит:
- приложение уже можно запускать и тестировать;
- часть функций уже работает стабильно;
- часть сценариев ещё дорабатывается;
- баги и шероховатости пока возможны.

### Что сейчас умеет

- показывать живую транскрипцию;
- анализировать речь через DeepSeek;
- выводить карточки-подсказки во время разговора;
- работать в нескольких режимах, включая офлайн-анализ;
- сохранять историю сессий и карточек.

### Требования

- macOS 13 Ventura и выше
- Apple Silicon или Intel Mac
- ключ DeepSeek API

### Быстрый старт

#### 1. Клонировать репозиторий

```bash
git clone git@github.com:Andrew821667/AI-Meeting-Copilot.git
cd AI-Meeting-Copilot
```

#### 2. Указать ключ DeepSeek

Пример переменных:
- `./backend/.env.example`

Рекомендуемый локальный вариант:

```bash
mkdir -p "$HOME/Library/Application Support/AIMeetingCopilot"
cat > "$HOME/Library/Application Support/AIMeetingCopilot/.env" <<'EOF_ENV'
AIMC_DEEPSEEK_API_KEY=your_deepseek_key_here
AIMC_DEEPSEEK_MODEL=deepseek-chat
EOF_ENV
```

#### 3. Собрать приложение

```bash
./tools/build_app_bundle.sh
```

После сборки приложение появится здесь:

```bash
dist/AIMeetingCopilot.app
```

#### 4. Запустить приложение

Откройте:

```bash
dist/AIMeetingCopilot.app
```

При первом запуске macOS может запросить доступы:
- к микрофону;
- к распознаванию речи;
- к записи экрана, если нужен захват аудио собеседника.

### Если нужен только backend

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=backend pytest -q backend/tests
python3 backend/main.py --socket /tmp/aimc.sock --exports-dir exports
```

### Как помочь проекту

Если хотите помочь, сейчас особенно полезны:
- тесты на разных версиях macOS;
- баг-репорты с точными шагами;
- замечания по UX и логике карточек;
- небольшие pull request'ы по стабильности и документации.

Полезные ссылки:
- правила совместной работы: `./CONTRIBUTING.md`
- production-checklist: `./docs/ops/production-readiness.md`

### Куда писать о проблемах

Если что-то сломалось или ведёт себя странно:
- откройте `Issue` в репозитории;
- по возможности приложите версию macOS, модель Mac, режим приложения и шаги воспроизведения.

## English

### What It Is

AI Meeting Copilot is a macOS app for meetings and conversations.
It listens to speech, shows live transcription, and suggests possible replies using DeepSeek.

In short: you talk, and the app helps you keep context and react faster during the meeting.

### Why It May Be Useful

- helps you avoid missing important details;
- gives quick suggestions during the conversation itself;
- reduces cognitive load when you need to listen, think, and respond at the same time.

### Who It Is For

This app may be useful if you:
- attend job interviews;
- run negotiations;
- hold consulting calls;
- join work meetings;
- want to analyze an offline conversation through the microphone.

### Project Status

The project is currently in `public beta` / final testing.

This means:
- the app can already be launched and tested;
- some features are already stable;
- some scenarios are still being refined;
- bugs and rough edges are still possible.

### What It Can Do Right Now

- show live transcription;
- analyze speech with DeepSeek;
- display real-time suggestion cards during a conversation;
- work in multiple modes, including offline analysis;
- save session and card history.

### Requirements

- macOS 13 Ventura or newer
- Apple Silicon or Intel Mac
- DeepSeek API key

### Quick Start

#### 1. Clone the repository

```bash
git clone git@github.com:Andrew821667/AI-Meeting-Copilot.git
cd AI-Meeting-Copilot
```

#### 2. Set your DeepSeek API key

Environment example:
- `./backend/.env.example`

Recommended local setup:

```bash
mkdir -p "$HOME/Library/Application Support/AIMeetingCopilot"
cat > "$HOME/Library/Application Support/AIMeetingCopilot/.env" <<'EOF_ENV'
AIMC_DEEPSEEK_API_KEY=your_deepseek_key_here
AIMC_DEEPSEEK_MODEL=deepseek-chat
EOF_ENV
```

#### 3. Build the app

```bash
./tools/build_app_bundle.sh
```

After the build, the app will appear here:

```bash
dist/AIMeetingCopilot.app
```

#### 4. Launch the app

Open:

```bash
dist/AIMeetingCopilot.app
```

On first launch, macOS may ask for permission to access:
- the microphone;
- speech recognition;
- screen recording, if you want to capture the other participant's audio.

### Backend Only

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
PYTHONPATH=backend pytest -q backend/tests
python3 backend/main.py --socket /tmp/aimc.sock --exports-dir exports
```

### How To Help

If you want to help, the most useful things right now are:
- testing on different macOS versions;
- bug reports with exact reproduction steps;
- UX feedback on cards and app behavior;
- small pull requests focused on stability and documentation.

Useful links:
- contributing guide: `./CONTRIBUTING.md`
- production checklist: `./docs/ops/production-readiness.md`

### Where To Report Problems

If something is broken or behaves strangely:
- open an `Issue` in this repository;
- if possible, include your macOS version, Mac model, app mode, and reproduction steps.

## Demo

> Screenshots will be added separately

## Roadmap

- [x] Stages 0–25: ASR, speaker diarization, LLM, CI/CD, macOS notarization
- [ ] Final testing and stabilization
- [ ] Public release v1.0

## Useful Scripts

- `./tools/smoke_test_backend.sh`
- `./tools/build_app_bundle.sh`
- `./tools/release_preflight.sh`
- `./tools/release_macos.sh`

## Technical Materials

- `docs/architecture/realtime-boundary.md`
- `docs/contracts/event-contract.md`
- `docs/contracts/events.schema.json`
- `docs/telemetry/slo-and-metrics.md`
- `docs/process/mvp-definition-of-done.md`
- `docs/process/stage-gates.md`
- `docs/process/stage-1-report.md`
- `docs/process/stage-2-report.md`
- `docs/process/stage-3-report.md`
- `docs/process/stage-4-report.md`
- `docs/process/stage-5-report.md`
- `docs/process/stage-6-report.md`
- `docs/process/stage-7-report.md`
- `docs/process/stage-8-report.md`
- `docs/process/stage-9-report.md`
- `docs/process/stage-10-report.md`
- `docs/process/stage-11-report.md`
- `docs/process/stage-12-report.md`
- `docs/process/stage-13-report.md`
- `docs/process/stage-14-report.md`
- `docs/process/stage-15-report.md`
- `docs/process/stage-16-report.md`
- `docs/process/stage-17-report.md`
- `docs/process/stage-18-report.md`
- `docs/process/stage-19-report.md`
- `docs/process/stage-20-report.md`
- `docs/process/stage-21-report.md`
- `docs/process/stage-22-report.md`
- `docs/process/stage-23-report.md`
- `docs/process/stage-24-report.md`
- `docs/process/stage-25-report.md`
