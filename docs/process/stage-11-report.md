# Stage 11 Report (Compliance onboarding v2)

## Scope
Усилить compliance-часть онбординга: версионировать подтверждение согласия и сделать подтверждение явным действием через чекбокс, чтобы исключить случайное принятие.

## Delivered
1. Версионированное согласие:
   - `PermissionsManager.currentConsentVersion = 2`
   - хранение `consent_ack_version` в `UserDefaults`
   - backward migration с legacy-флага `consent_ack_v1` -> версия `1`
   - согласие считается действительным только если `stored_version >= currentConsentVersion`
   - файл: `Sources/AIMeetingCopilotCore/Permissions/PermissionsManager.swift`
2. Инъекции статусов разрешений для тестируемости:
   - `microphoneStatusProvider`
   - `screenRecordingStatusProvider`
   - файл: `Sources/AIMeetingCopilotCore/Permissions/PermissionsManager.swift`
3. Обновленный onboarding UI (русский):
   - чекбокс явного подтверждения права на запись/анализ
   - кнопка `Подтвердить согласие` активна только при установленном чекбоксе
   - статусный текст с номером версии согласия `v2`
   - файл: `Sources/AIMeetingCopilotCore/UI/OnboardingChecklistView.swift`
4. Swift unit tests:
   - проверка, что устаревшая версия согласия не проходит
   - проверка, что `acceptOneTimeAcknowledgement()` записывает текущую версию
   - файл: `Tests/AIMeetingCopilotTests/PermissionsManagerTests.swift`

## Verification
- `PYTHONPATH=backend pytest -q backend/tests` -> pass
- `python3 -m py_compile backend/main.py backend/session_history_store.py` -> pass

## Notes
1. Все пользовательские формулировки onboarding остаются на русском языке.
2. Swift build/test в этой среде ограничен sandbox/toolchain mismatch, поэтому проверка Swift unit tests не выполнялась локально в рамках CI этой сессии.
