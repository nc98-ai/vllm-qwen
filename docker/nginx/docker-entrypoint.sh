#!/usr/bin/env sh
set -eu

: "${NGINX_BACKEND_UPSTREAM:=vllm:8080}"
: "${NGINX_HTTP_LISTEN_PORT:=80}"
: "${NGINX_HTTPS_LISTEN_PORT:=443}"

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

envsubst '${NGINX_BACKEND_UPSTREAM} ${NGINX_HTTP_LISTEN_PORT} ${NGINX_HTTPS_LISTEN_PORT}' \
  < /etc/nginx/templates/nginx.conf.template \
  > /etc/nginx/nginx.conf

exec nginx -g 'daemon off;'
