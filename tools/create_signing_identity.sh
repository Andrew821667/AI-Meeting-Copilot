#!/usr/bin/env bash
# Создаёт локальную самоподписанную идентичность для подписи сборок.
#
# Зачем: при ad-hoc подписи macOS считает каждую пересборку новым приложением
# (меняется cdhash) и сбрасывает выданные разрешения (микрофон, распознавание
# речи). Подпись стабильным сертификатом делает «designated requirement»
# устойчивым — разрешения переживают переустановку.
#
# Одноразово. Ключ и сертификат кладутся в login keychain. Флаг -A разрешает
# codesign использовать ключ без запроса пароля (локальный dev-ключ).
set -euo pipefail

CERT_NAME="${AIMC_SIGN_IDENTITY:-AIMeetingCopilot Local Signing}"
KEYCHAIN="$(security default-keychain | tr -d ' "')"
OPENSSL="/usr/bin/openssl"   # системный LibreSSL — совместимый p12 для security import

if security find-identity -v -p codesigning | grep -qF "$CERT_NAME"; then
  echo "Идентичность уже существует: $CERT_NAME"
  exit 0
fi

echo "Создаю самоподписанную идентичность: $CERT_NAME"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/openssl.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $CERT_NAME
[ext]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

"$OPENSSL" req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
  -keyout "$WORK/key.pem" -out "$WORK/cert.pem" -config "$WORK/openssl.cnf" 2>/dev/null

"$OPENSSL" pkcs12 -export -out "$WORK/identity.p12" \
  -inkey "$WORK/key.pem" -in "$WORK/cert.pem" \
  -name "$CERT_NAME" -passout pass:aimc

# -A: любой процесс (в т.ч. codesign) может использовать ключ без запроса пароля.
security import "$WORK/identity.p12" -k "$KEYCHAIN" -P aimc -A

echo "Готово. Идентичность добавлена в: $KEYCHAIN"
security find-identity -v -p codesigning | grep -F "$CERT_NAME" || true
