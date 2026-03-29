#!/usr/bin/env sh
set -eu

: "${NGINX_BACKEND_UPSTREAM:=vllm:8080}"
: "${NGINX_HTTPS_LISTEN_PORT:=443}"
: "${NGINX_BACKEND_READY_TIMEOUT:=900}"
: "${NGINX_BACKEND_READY_INTERVAL:=5}"
export NGINX_API_KEY="${NGINX_API_KEY:-}"

write_secret_file() {
  src_file="$1"
  env_value="$2"
  dest_file="$3"
  dest_mode="$4"

  if [ -f "$src_file" ]; then
    cp "$src_file" "$dest_file"
  elif [ -n "$env_value" ]; then
    printf '%s' "$env_value" > "$dest_file"
  else
    return 1
  fi

  chmod "$dest_mode" "$dest_file"
  return 0
}

write_secret_file "/run/secrets/NGINX_SSL_KEY" "${NGINX_SSL_KEY:-}" \
  "/etc/nginx/certs/server.key" 600 || true
write_secret_file "/run/secrets/NGINX_SSL_CERT" "${NGINX_SSL_CERT:-}" \
  "/etc/nginx/certs/server.crt" 644 || true

if ! write_secret_file "/run/secrets/NGINX_SSL_FULLCHAIN" "${NGINX_SSL_FULLCHAIN:-}" \
  "/etc/nginx/certs/server_fullchain.crt" 644; then
  if [ -f /etc/nginx/certs/server.crt ]; then
    cp /etc/nginx/certs/server.crt /etc/nginx/certs/server_fullchain.crt
    chmod 644 /etc/nginx/certs/server_fullchain.crt
  fi
fi

if [ -z "${NGINX_API_KEY}" ] && [ -f /run/secrets/vllm_api_key ]; then
  NGINX_API_KEY="$(cat /run/secrets/vllm_api_key)"
  export NGINX_API_KEY
fi

if [ -z "${NGINX_API_KEY}" ]; then
  echo "Missing required API key for nginx auth (/run/secrets/vllm_api_key or NGINX_API_KEY)." >&2
  exit 1
fi

envsubst '${NGINX_BACKEND_UPSTREAM} ${NGINX_HTTPS_LISTEN_PORT} ${NGINX_API_KEY}' \
  < /etc/nginx/templates/nginx.conf.template \
  > /etc/nginx/nginx.conf

wait_for_backend() {
  backend_url="http://${NGINX_BACKEND_UPSTREAM}/v1/models"
  attempts=$((NGINX_BACKEND_READY_TIMEOUT / NGINX_BACKEND_READY_INTERVAL))

  if [ "$attempts" -le 0 ]; then
    attempts=1
  fi

  i=1
  while [ "$i" -le "$attempts" ]; do
    if curl -fsS "$backend_url" >/dev/null 2>&1; then
      return 0
    fi

    echo "Waiting for backend readiness at ${backend_url} (${i}/${attempts})"
    sleep "$NGINX_BACKEND_READY_INTERVAL"
    i=$((i + 1))
  done

  echo "Backend did not become ready in time: ${backend_url}" >&2
  return 1
}

wait_for_backend

exec nginx -g 'daemon off;'
