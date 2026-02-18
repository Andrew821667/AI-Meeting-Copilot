# Stage 16 Report (BlackHole fallback + silence watchdog)

## Scope
Добавить устойчивый fallback для системного аудио: если `ScreenCaptureKit` не даёт сигнал длительное время, переключать захват в режим `BlackHole` без падения сессии.

## Delivered
1. `SystemAudioCaptureService`:
   - добавлен silence watchdog (`10s` низкого сигнала в режиме SCK)
   - автоматический перевод режима в `CaptureMode.blackHole`
   - callback `onCaptureModeChanged(mode, reason)` для UI/VM
   - файл: `Sources/AIMeetingCopilotCore/Audio/SystemAudioCaptureService.swift`
2. `MainViewModel`:
   - обработка смены режима от `SystemAudioCaptureService`
   - обновление capture индикатора + русское сообщение причины fallback
   - файл: `Sources/AIMeetingCopilotCore/UI/MainViewModel.swift`

## Result
Захват не «молчит бесконечно» при проблемах SCK: пользователь видит причину и режим автоматически деградирует в fallback.
