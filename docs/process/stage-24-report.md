# Stage 24 Report - Release Automation

Дата: 2026-02-18

## Что сделано

- Добавлен скрипт сборки app bundle:
  - `tools/build_app_bundle.sh`
  - собирает release binary через SwiftPM;
  - формирует `.app` структуру;
  - добавляет `Info.plist` и (опционально) упаковывает backend.
- Добавлен preflight-скрипт релиза:
  - `tools/release_preflight.sh`
  - проверяет инструменты, codesign identity и параметры notarization.
- Расширен `tools/release_macos.sh`:
  - поддержка notarization через `AIMC_NOTARY_PROFILE`;
  - поддержка notarization через API key (`AIMC_NOTARY_KEY_ID`, `AIMC_NOTARY_ISSUER_ID`, `AIMC_NOTARY_KEY_PATH`).
- Добавлен release workflow:
  - `.github/workflows/release-macos.yml`
  - сборка app, загрузка unsigned artifact;
  - при наличии секретов: подпись, notarization и upload signed artifact.
- Обновлены docs:
  - `docs/ops/release-macos.md`
  - `docs/ops/production-readiness.md`

## Проверки

- `bash -n tools/build_app_bundle.sh` -> OK
- `bash -n tools/release_preflight.sh` -> OK
- `bash -n tools/release_macos.sh` -> OK

## Остаток до финального дистрибутива

- Завести GitHub secrets для signing/notary (см. release workflow).
- Выполнить релиз по тегу `v*` или через `workflow_dispatch`.
