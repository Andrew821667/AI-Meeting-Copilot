# Stage 14 Report (ASR provider switch: WhisperKit / Qwen3-ASR)

## Scope
Подготовить Phase 4 foundation: добавить каркас второго ASR-провайдера и переключение провайдера в UI без рефакторинга оркестратора.

## Delivered
1. Расширен mock ASR provider:
   - `MockASRProvider` теперь поддерживает кастомный сценарий реплик
   - файл: `Sources/AIMeetingCopilotCore/Core/MockASRProvider.swift`
2. Добавлен `Qwen3ASRProvider` (scaffold):
   - отдельная реализация `ASRProvider`
   - пока работает через mock fallback с отдельным техническим сценарием
   - файл: `Sources/AIMeetingCopilotCore/Core/Qwen3ASRProvider.swift`
3. Фабрика провайдеров:
   - `ASRProviderFactory.make(optionID:)`
   - поддержка `whisperkit` и `qwen3_asr`
   - файл: `Sources/AIMeetingCopilotCore/Core/ASRProviderFactory.swift`
4. Модель ASR-опций:
   - `ASRProviderOption` с русскими названиями для UI
   - файл: `Sources/AIMeetingCopilotCore/Models/ASRProviderOption.swift`
5. Интеграция в `MainViewModel`:
   - `selectedASRProviderID` + `availableASRProviders`
   - переключение провайдера в idle-состоянии через factory
   - файл: `Sources/AIMeetingCopilotCore/UI/MainViewModel.swift`
6. UI (русский):
   - новый `Picker("ASR", ...)` в панели управления
   - блокировка изменения во время активной/поставленной на паузу сессии
   - файл: `Sources/AIMeetingCopilotCore/UI/ContentView.swift`
7. Swift unit tests:
   - `ASRProviderFactoryTests` (unknown -> Whisper, `qwen3_asr` -> Qwen3)
   - файл: `Tests/AIMeetingCopilotTests/ASRProviderFactoryTests.swift`

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/telemetry.py` -> pass

## Notes
1. Реальная runtime-интеграция `mlx-qwen3-asr` остается следующей задачей Phase 4; в этом этапе зафиксирован стабильный контракт и UI-переключение.
2. Все пользовательские подписи в UI остаются на русском языке.
