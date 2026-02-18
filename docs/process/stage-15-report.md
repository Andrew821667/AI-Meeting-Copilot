# Stage 15 Report (ScreenCaptureKit system audio capture)

## Scope
Перевести системный аудиозахват с таймерного stub на реальный `ScreenCaptureKit` поток (SCK path) с безопасной деградацией.

## Delivered
1. `SystemAudioCaptureService` upgraded:
   - сервис теперь наследуется от `NSObject` и реализует `SCStreamOutput`
   - реальный запуск `SCStream` с `capturesAudio = true`
   - обработка `CMSampleBuffer` аудио-чанков
   - файл: `Sources/AIMeetingCopilotCore/Audio/SystemAudioCaptureService.swift`
2. Level emitter preserved:
   - `AudioLevelEvent` продолжает отправляться раз в секунду
   - для SCK используется оценка уровня по реальным входящим audio sample buffers
   - при устаревании потока (`>2s` без аудио) уровень сбрасывается к `0`
3. Graceful fallback:
   - если `ScreenCaptureKit` недоступен/ошибся старт/нет source, сервис не падает
   - уровень системного аудио уходит в `0`, остальная сессия продолжает работу
4. Совместимость режимов:
   - `micOnly` -> системный уровень `0`
   - `blackHole` пока остается стабильным stub-уровнем до отдельного этапа BlackHole runtime wiring.

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/telemetry.py` -> pass

## Notes
1. Это реальный SCK ingestion path для системного аудио; дальнейшее улучшение точности RMS возможно отдельным шагом.
2. Swift build/test в текущей среде ограничен sandbox/toolchain mismatch, поэтому runtime-проверка SCK проводится на целевой macOS машине.
