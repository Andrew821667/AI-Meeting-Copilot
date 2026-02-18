# Stage 7 Report (Learning mode + exclude list)

## Scope
Реализовать ручную обратную связь по карточкам и исключение повторяющихся паттернов в рамках текущего профиля, без автоподстройки весов.

## Delivered
1. SQLite-хранилище обратной связи:
   - таблица `session_feedback` (upsert по `session_id + card_id`)
   - таблица `excluded_phrases` (per-profile exclude list)
   - файл: `backend/feedback_store.py`
2. Backend-события для Learning mode:
   - `card_feedback`
   - `exclude_phrase`
   - файл: `backend/main.py`
3. Runtime-интеграция feedback/exclude:
   - запись фидбека в SQLite
   - загрузка exclude list при старте сессии по выбранному профилю
   - сохранение новых исключений
   - файл: `backend/main.py`
4. Trigger suppression по exclude list:
   - нормализация фраз
   - блокировка срабатывания до LLM вызова
   - файл: `backend/orchestrator.py`
5. Метрики фидбека:
   - `useful_feedback_count`
   - `useless_feedback_count`
   - `excluded_feedback_count`
   - файл: `backend/telemetry.py`
6. UI Learning mode на русском:
   - кнопки `Полезно`, `Бесполезно`, `Не показывать похожее`
   - отправка новых UDS-событий из `MainViewModel`
   - файлы:
     - `Sources/AIMeetingCopilotCore/UI/InsightCardView.swift`
     - `Sources/AIMeetingCopilotCore/UI/MainViewModel.swift`
     - `Sources/AIMeetingCopilotCore/UI/ContentView.swift`
7. Тесты:
   - `backend/tests/test_feedback_store.py`
   - `backend/tests/test_orchestrator_exclude.py`

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/orchestrator.py backend/telemetry.py backend/feedback_store.py backend/tests/test_feedback_store.py backend/tests/test_orchestrator_exclude.py` -> pass

## Notes
1. Это ручной learning mode без автоматического изменения весов триггеров.
2. Exclude list хранится по профилю и применяется к следующим сессиям этого профиля.
