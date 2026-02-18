# Stage 13 Report (Dynamic timeout warning in UI)

## Scope
Добавить динамическое предупреждение о деградации realtime-LLM, если latency начинает выходить за целевой диапазон.

## Delivered
1. Backend dynamic timeout detector:
   - `TelemetryCollector` хранит последние 3 LLM latency и вычисляет p95
   - при `p95 > 2000ms` формирует runtime warning (один раз до восстановления)
   - новая метрика: `dynamic_timeout_warning_count`
   - файл: `backend/telemetry.py`
2. UDS runtime warning event:
   - backend отправляет `{"type":"runtime_warning","payload":{"message":...}}`
   - файл: `backend/main.py`
3. Swift UDS client handling:
   - добавлен callback `onRuntimeWarning`
   - декодирование `runtime_warning`
   - файл: `Sources/AIMeetingCopilotCore/Core/UDSEventClient.swift`
4. UI integration:
   - `MainViewModel` получает предупреждение и показывает его 8 секунд
   - `ContentView` отображает русское предупреждение в оранжевом стиле
   - файлы:
     - `Sources/AIMeetingCopilotCore/UI/MainViewModel.swift`
     - `Sources/AIMeetingCopilotCore/UI/ContentView.swift`
5. Tests:
   - расширен `backend/tests/test_telemetry.py`
   - проверка триггера warning и метрики `dynamic_timeout_warning_count`

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/telemetry.py backend/tests/test_telemetry.py` -> pass

## Notes
1. Предупреждение не дублируется без новых LLM-вызовов.
2. После серии быстрых вызовов warning-state сбрасывается автоматически.
