#!/usr/bin/env sh
set -eu

: "${NGINX_BACKEND_UPSTREAM:=vllm:8080}"
: "${NGINX_HTTPS_LISTEN_PORT:=443}"
: "${NGINX_BACKEND_READY_TIMEOUT:=900}"
: "${NGINX_BACKEND_READY_INTERVAL:=5}"
: "${NGINX_BACKEND_WARMUP_ENABLED:=true}"
: "${NGINX_BACKEND_WARMUP_PROMPT:=warmup}"
: "${NGINX_BACKEND_WARMUP_MAX_TOKENS:=1}"
: "${NGINX_BACKEND_WARMUP_TIMEOUT:=120}"
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

# shellcheck disable=SC2016
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

warmup_backend() {
  if [ "${NGINX_BACKEND_WARMUP_ENABLED}" != "true" ]; then
    return 0
  fi

  models_url="http://${NGINX_BACKEND_UPSTREAM}/v1/models"
  completions_url="http://${NGINX_BACKEND_UPSTREAM}/v1/completions"

  model_id="$(
    curl -fsS --max-time "${NGINX_BACKEND_WARMUP_TIMEOUT}" "${models_url}" \
      | grep -o '"id":"[^"]*"' \
      | head -n 1 \
      | cut -d'"' -f4 \
      | head -n 1
  )"

  if [ -z "${model_id}" ]; then
    echo "Unable to resolve model id from ${models_url}" >&2
    return 1
  fi

  warmup_payload=$(printf '{"model":"%s","prompt":"%s","max_tokens":%s,"temperature":0}' \
    "${model_id}" "${NGINX_BACKEND_WARMUP_PROMPT}" "${NGINX_BACKEND_WARMUP_MAX_TOKENS}")

  echo "Sending warmup request to backend model ${model_id}"
  curl -fsS --max-time "${NGINX_BACKEND_WARMUP_TIMEOUT}" \
    -H "Content-Type: application/json" \
    -d "${warmup_payload}" \
    "${completions_url}" >/dev/null
}

warmup_backend

exec nginx -g 'daemon off;'
