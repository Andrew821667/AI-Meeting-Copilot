# Stage 12 Report (Редактор exclude list в UI)

## Scope
Добавить ручное управление exclude list для текущего профиля прямо в интерфейсе: просмотр, добавление и удаление фраз-исключений.

## Delivered
1. Локальное хранилище исключений в Swift:
   - `ExcludePhraseStore` (SQLite `exports/feedback.sqlite3`)
   - операции: load/add/remove
   - нормализация фраз по тем же правилам (lowercase, punctuation cleanup, whitespace collapse)
   - файл: `Sources/AIMeetingCopilotCore/Core/ExcludePhraseStore.swift`
2. Интеграция в `MainViewModel`:
   - `excludedPhrases` state
   - методы:
     - `reloadExcludedPhrases()`
     - `addManualExcludedPhrase(_:)`
     - `removeManualExcludedPhrase(_:)`
   - при `excludeActiveCardPattern()` фраза сразу сохраняется и в локальный store
   - файл: `Sources/AIMeetingCopilotCore/UI/MainViewModel.swift`
3. UI-редактор исключений (русский):
   - кнопка `Исключения профиля` в панели управления
   - sheet `Исключения триггеров`:
     - текстовое поле + `Добавить`
     - список текущих исключений
     - `Удалить` для каждой фразы
   - файл: `Sources/AIMeetingCopilotCore/UI/ContentView.swift`
4. Swift unit tests:
   - `ExcludePhraseStoreTests`
   - проверка normalize/add/load/remove
   - файл: `Tests/AIMeetingCopilotTests/ExcludePhraseStoreTests.swift`

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/session_history_store.py` -> pass

## Notes
1. Управление исключениями теперь возможно без активной сессии.
2. Все пользовательские тексты и элементы взаимодействия остаются на русском языке.
