# Stage 10 Report (История сессий в SQLite)

## Scope
Перевести историю сессий с файлового сканирования `exports/*.json` на SQLite-индекс, чтобы история была стабильной и быстрой на больших объемах.

## Delivered
1. Backend session history store:
   - новый модуль `backend/session_history_store.py`
   - таблица `session_history` в `exports/sessions.sqlite3`
   - upsert по `session_id`
2. Запись истории при завершении сессии:
   - `backend/main.py` теперь сохраняет итог сессии в SQLite:
     - profile, started/ended timestamps
     - total/fallback cards
     - пути к JSON/MD/PDF экспорту
3. Swift history reader из SQLite:
   - `SessionHistoryStore` теперь читает историю из `exports/sessions.sqlite3`
   - сортировка по `ended_at DESC`
   - fallback на legacy-режим (скан JSON), если SQLite недоступен
   - файл: `Sources/AIMeetingCopilotCore/Core/SessionHistoryStore.swift`
4. Backend unit test:
   - `backend/tests/test_session_history_store.py`
   - проверка upsert и корректности сохраненных полей.

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/session_history_store.py backend/tests/test_session_history_store.py` -> pass

## Result
Ограничение Stage 6 закрыто: история больше не зависит только от сканирования JSON-файлов и поддерживает более надежный индексированный источник данных.
