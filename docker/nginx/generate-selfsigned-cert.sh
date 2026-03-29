#!/usr/bin/env bash
set -Eeuo pipefail

CERT_DIR="${1:-./certs}"
COMMON_NAME="${2:-localhost}"
DAYS_VALID="${DAYS_VALID:-825}"

mkdir -p "${CERT_DIR}"

openssl req \
  -x509 \
  -nodes \
  -newkey rsa:4096 \
  -sha256 \
  -days "${DAYS_VALID}" \
  -keyout "${CERT_DIR}/server.key" \
  -out "${CERT_DIR}/server.crt" \
  -subj "/C=NC/ST=Noumea/L=Noumea/O=Ragingest/OU=IT/CN=${COMMON_NAME}" \
  -addext "subjectAltName=DNS:${COMMON_NAME},DNS:localhost,IP:127.0.0.1"

cp "${CERT_DIR}/server.crt" "${CERT_DIR}/server_fullchain.crt"

chmod 600 "${CERT_DIR}/server.key"
chmod 644 "${CERT_DIR}/server.crt" "${CERT_DIR}/server_fullchain.crt"

echo "Certificats generes dans ${CERT_DIR}"
