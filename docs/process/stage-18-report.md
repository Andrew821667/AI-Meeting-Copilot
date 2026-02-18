# Stage 18 Report (Diarization runtime signal path)

## Scope
Подключить runtime-сигналы диаризации до quality gates, чтобы backend реально получал `THEM_A/THEM_B` и confidence, а не только общий `THEM`.

## Delivered
1. `MockASRProvider`:
   - поддержка `speakerPlan` и speaker-confidence per utterance
   - partial/final сегменты теперь могут идти как `THEM_A`/`THEM_B`
   - файл: `Sources/AIMeetingCopilotCore/Core/MockASRProvider.swift`
2. `Qwen3ASRProvider`:
   - отдельный speaker plan для технического сценария
   - файл: `Sources/AIMeetingCopilotCore/Core/Qwen3ASRProvider.swift`

## Result
`DiarizationGate` в backend теперь обрабатывает реалистичный runtime stream с атрибуцией спикеров и confidence.
