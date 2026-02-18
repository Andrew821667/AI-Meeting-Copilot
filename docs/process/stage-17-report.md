# Stage 17 Report (Semantic + Emotion optional detectors)

## Scope
Добавить optional сигналы `semantic_shift` и `emotion_boost` в scoring pipeline с runtime-отключением в degraded-состоянии.

## Delivered
1. Новые модули:
   - `backend/semantic_detector.py`
   - `backend/emotion_detector.py`
2. Интеграция в scorer:
   - `TriggerScorer` теперь учитывает semantic/emotion при включенных флагах профиля
   - поддержка runtime toggle `set_optional_signals_enabled(...)`
   - файл: `backend/trigger_scorer.py`
3. Расширение профилей:
   - флаги `semantic_enabled`, `emotion_enabled` в `Profile`
   - `tech_sync` по умолчанию с `semantic_enabled=true`
   - runtime settings экспортируют оба флага
   - файл: `backend/profile_loader.py`
4. Авто-degrade на system state:
   - оркестратор отключает optional сигналы при low battery / high thermal
   - файл: `backend/orchestrator.py`
5. Тесты:
   - `backend/tests/test_optional_detectors.py`
   - `backend/tests/test_orchestrator_degraded_mode.py`
   - обновление `backend/tests/test_profile_loader.py`

## Result
Pipeline готов к Phase 2 signals без тяжёлых зависимостей и с безопасной деградацией при ограничениях системы.
