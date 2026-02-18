#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $1"
  exit 1
}

warn() {
  echo "WARN: $1"
}

pass() {
  echo "OK: $1"
}

command -v swift >/dev/null 2>&1 || fail "swift не найден"
command -v codesign >/dev/null 2>&1 || fail "codesign не найден"
command -v xcrun >/dev/null 2>&1 || fail "xcrun не найден"
pass "Базовые инструменты установлены"

if [[ -n "${AIMC_CODESIGN_IDENTITY:-}" ]]; then
  if security find-identity -v -p codesigning | grep -Fq "$AIMC_CODESIGN_IDENTITY"; then
    pass "Найден codesign identity: $AIMC_CODESIGN_IDENTITY"
  else
    fail "AIMC_CODESIGN_IDENTITY не найден в keychain"
  fi
else
  warn "AIMC_CODESIGN_IDENTITY не задан"
fi

if [[ -n "${AIMC_NOTARY_PROFILE:-}" ]]; then
  if xcrun notarytool history --keychain-profile "$AIMC_NOTARY_PROFILE" >/dev/null 2>&1; then
    pass "Найден notary profile: $AIMC_NOTARY_PROFILE"
  else
    fail "AIMC_NOTARY_PROFILE задан, но notarytool не может использовать его"
  fi
elif [[ -n "${AIMC_NOTARY_KEY_ID:-}" && -n "${AIMC_NOTARY_ISSUER_ID:-}" && -n "${AIMC_NOTARY_KEY_PATH:-}" ]]; then
  if [[ -f "$AIMC_NOTARY_KEY_PATH" ]]; then
    pass "Найдены API key параметры notarization"
  else
    fail "AIMC_NOTARY_KEY_PATH не существует: $AIMC_NOTARY_KEY_PATH"
  fi
else
  warn "Не заданы параметры notarization (AIMC_NOTARY_PROFILE или AIMC_NOTARY_KEY_*)"
fi

pass "Preflight завершён"
