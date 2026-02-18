# Stage 9 Report (Calendar auto-profile via EventKit)

## Scope
Интегрировать календарь macOS (EventKit), чтобы приложение могло предлагать профиль встречи по названию ближайшего события и применять его в один клик.

## Delivered
1. Calendar suggester service:
   - `CalendarProfileSuggester` на EventKit
   - запрос доступа к календарю
   - поиск ближайших событий в окне [-30 мин, +8 часов]
   - матчинг названия встречи в профиль (`interview_*`, `tech_sync`, `sales`, `consulting`, `negotiation`)
   - файл: `Sources/AIMeetingCopilotCore/Core/CalendarProfileSuggester.swift`
2. Интеграция в `MainViewModel`:
   - статус календаря (`calendarStatusText`)
   - предложенный профиль (`calendarSuggestedProfileID`)
   - методы:
     - `refreshCalendarSuggestion(autoApply:)`
     - `applyCalendarSuggestedProfile()`
   - авто-применение только в безопасном режиме:
     - сессия не запущена
     - профиль не менялся вручную
     - текущий профиль дефолтный (`negotiation`)
   - файл: `Sources/AIMeetingCopilotCore/UI/MainViewModel.swift`
3. UI на русском:
   - новый блок `Календарь`
   - кнопки `Обновить из календаря` и `Применить профиль`
   - отображение статуса/подсказки по ближайшей встрече
   - файл: `Sources/AIMeetingCopilotCore/UI/ContentView.swift`
4. Unit tests (mapping logic):
   - `CalendarProfileSuggesterTests.swift`
   - проверка: candidate interview, tech sync, generic title (nil)
   - файл: `Tests/AIMeetingCopilotTests/CalendarProfileSuggesterTests.swift`

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/pdf_export.py` -> pass

## Notes
1. Swift build/tests в текущей среде остаются недоступны из-за sandbox и несовпадения toolchain/SDK.
2. Даже без доступа к календарю приложение продолжает работать; показывается русскоязычный статус `Календарь: доступ не предоставлен`.
