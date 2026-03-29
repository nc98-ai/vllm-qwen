#!/bin/bash
# Bootstrap runtime pour les conteneurs deployes via le runner self-hosted.
# Le script complete ce que Docker Compose ne fait pas seul:
# - regenerer les fichiers /app/cred/*.env attendus par les scripts Python.
# Les variables issues de .env et .env_api sont deja injectees par `env_file`
# dans docker compose. Ici, on se concentre sur les fichiers cred et secrets.
set -Eeuo pipefail

log() {
  printf '[entrypoint] %s\n' "$*"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

read_secret_file() {
  local file_path="$1"
  if [ -f "$file_path" ]; then
    cat "$file_path"
  fi
}

load_env_file() {
  local file_path="$1"
  local line key value normalized_key
  if [ ! -f "$file_path" ]; then
    return 0
  fi

  log "chargement de $file_path"

  # Parse un format dotenv tolerant:
  # - commentaires et lignes vides
  # - espaces autour de '='
  # - cles historiques en minuscules comme client_id
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    line="$(trim "$line")"

    if [ -z "$line" ] || [[ "$line" == \#* ]]; then
      continue
    fi

    if [[ "$line" != *"="* ]]; then
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="$(trim "$key")"
    value="$(trim "$value")"

    if [[ "$value" == \"*\" && "$value" == *\" ]]; then
      value="${value:1:-1}"
    elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
      value="${value:1:-1}"
    fi

    normalized_key="$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
    case "$normalized_key" in
      TENANT_ID|CLIENT_ID|CLIENT_SECRET|CONFLUENCE_API_KEY|CONFLUENCE_HTTPS_INSECURE|CONFLUENCE_CA_BUNDLE|CONFLUENCE_PDF_METHOD|CONFLUENCE_WKHTMLTOPDF_PATH)
        export "$normalized_key=$value"
        ;;
    esac
  done < "$file_path"
}

write_spo_cred_file() {
  local target="/app/cred/spo.env"
  local spo_client_secret=""
  if [ ! -d /app/cred ]; then
    return 0
  fi

  # Le secret sensible est lu depuis /run/secrets/SPO_CLIENT_SECRET puis
  # mappe vers CLIENT_SECRET dans le fichier final attendu par la collecte.
  spo_client_secret="$(read_secret_file "/run/secrets/SPO_CLIENT_SECRET")"

  # Le pipeline SPO lit un fichier env dedie; on le regenere a partir des
  # variables runtime non sensibles et du secret fichier si present.
  if [ -n "${TENANT_ID:-}" ] || [ -n "${CLIENT_ID:-}" ] || [ -n "$spo_client_secret" ]; then
    cat > "$target" <<EOF
TENANT_ID=${TENANT_ID:-}
CLIENT_ID=${CLIENT_ID:-}
CLIENT_SECRET=${spo_client_secret}
EOF
    chmod 600 "$target"
    log "fichier d'identifiants SPO regenere: $target"
  fi
}

write_confluence_cred_file() {
  local target="/app/cred/confluence.env"
  if [ ! -d /app/cred ]; then
    return 0
  fi

  # Meme principe pour Confluence: on persiste les valeurs necessaires dans
  # le format attendu par la collecte.
  if [ -n "${CONFLUENCE_API_KEY:-}" ]; then
    cat > "$target" <<EOF
CONFLUENCE_API_KEY=${CONFLUENCE_API_KEY:-}
CONFLUENCE_HTTPS_INSECURE=${CONFLUENCE_HTTPS_INSECURE:-false}
CONFLUENCE_CA_BUNDLE=${CONFLUENCE_CA_BUNDLE:-}
CONFLUENCE_PDF_METHOD=${CONFLUENCE_PDF_METHOD:-confluence}
CONFLUENCE_WKHTMLTOPDF_PATH=${CONFLUENCE_WKHTMLTOPDF_PATH:-}
EOF
    chmod 600 "$target"
    log "fichier d'identifiants Confluence regenere: $target"
  fi
}

main() {
  # 1. Recharge les fichiers de credentials montes depuis le host.
  if [ -d /app/cred ]; then
    shopt -s nullglob
    for cred_file in /app/cred/*.env; do
      load_env_file "$cred_file"
    done
    shopt -u nullglob
  fi

  # 2. Regenerer les fichiers cred permet de garder une interface stable pour
  # les scripts applicatifs, meme si l'injection vient maintenant du runner.
  write_spo_cred_file
  write_confluence_cred_file

  # 3. Transfere l'execution au CMD/command du conteneur.
  log "demarrage de la commande: $*"
  exec "$@"
}

main "$@"
