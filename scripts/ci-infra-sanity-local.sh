#!/usr/bin/env bash
set -Eeuo pipefail

# Local equivalent of CI infra checks.
# This script is intentionally non-destructive:
# - no compose up/down
# - no container removal
# - only lint/config checks and one ephemeral docker run --rm

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

CLEANUP_IMAGES=1

usage() {
  cat <<'EOF'
Usage: bash scripts/ci-infra-sanity-local.sh [--cleanup-images]

Options:
  --no-cleanup-images, -n  Keep ci-local nginx test images after checks.
  --help, -h            Show this help and exit.
EOF
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --no-cleanup-images|-n)
      CLEANUP_IMAGES=0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

log() {
  printf '[ci-local] %s\n' "$*"
}

require_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    printf 'Missing required command: %s\n' "${cmd}" >&2
    return 1
  fi
}

run_shellcheck() {
  local -a files=("$@")
  if [[ "${#files[@]}" -eq 0 ]]; then
    return 0
  fi

  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck "${files[@]}"
    return 0
  fi

  log "shellcheck not found locally, using containerized shellcheck"
  "${ENGINE}" run --rm -v "${ROOT_DIR}:/work:Z" -w /work \
    docker.io/koalaman/shellcheck-alpine:stable \
    shellcheck "${files[@]}"
}

run_yamllint() {
  local config="{extends: default, rules: {line-length: disable, truthy: disable, trailing-spaces: disable, document-start: disable, comments-indentation: disable, new-line-at-end-of-file: disable}}"
  if command -v yamllint >/dev/null 2>&1; then
    yamllint -d "${config}" .github/workflows docker/docker-compose-vllm-nginx.yml
    return 0
  fi

  log "yamllint not found locally, using containerized yamllint"
  "${ENGINE}" run --rm -v "${ROOT_DIR}:/work:Z" -w /work \
    docker.io/cytopia/yamllint:latest \
    -d "${config}" .github/workflows docker/docker-compose-vllm-nginx.yml
}

cleanup_old_ci_images() {
  local current_image_tag="$1"
  local img
  local -a images=()

  while IFS= read -r img; do
    if [[ -n "${img}" ]]; then
      images+=("${img}")
    fi
  done < <("${ENGINE}" image ls --format '{{.Repository}}:{{.Tag}}' | grep 'nginx-vllm-qwen:ci-local-' || true)

  if [[ "${#images[@]}" -eq 0 ]]; then
    log "No old ci-local images to clean"
    return 0
  fi

  log "Cleaning old ci-local images"
  for img in "${images[@]}"; do
    if [[ "${img}" == *":<none>" ]]; then
      continue
    fi
    if [[ "${img}" == "${current_image_tag}" ]]; then
      continue
    fi
    "${ENGINE}" image rm "${img}" >/dev/null 2>&1 || true
  done
}

print_install_hints() {
  cat >&2 <<'EOF'
Install hints:
- Debian/Ubuntu:
  sudo apt-get update && sudo apt-get install -y shellcheck yamllint
- RHEL/Rocky/Fedora:
  sudo dnf install -y ShellCheck yamllint
- Arch:
  sudo pacman -S --needed shellcheck yamllint

If yamllint is unavailable in your package manager:
  python3 -m pip install --user yamllint
EOF
}

if command -v docker >/dev/null 2>&1; then
  ENGINE="docker"
elif command -v podman >/dev/null 2>&1; then
  ENGINE="podman"
else
  echo "Missing container engine: docker or podman is required." >&2
  exit 1
fi

missing=0
for cmd in find openssl; do
  if ! require_cmd "${cmd}"; then
    missing=1
  fi
done

if [[ "${missing}" -ne 0 ]]; then
  print_install_hints
  exit 1
fi

if [[ "${ENGINE}" == "docker" ]]; then
  COMPOSE_CMD=(docker compose)
else
  COMPOSE_CMD=(podman compose)
fi

IMAGE_TAG="nginx-vllm-qwen:ci-local-$(date +%Y%m%d%H%M%S)"

log "ShellCheck"
mapfile -t shell_files < <(find . -type f -name "*.sh" \
  -not -path "./actions-runner/*" \
  -not -path "./actions-runner/**")
run_shellcheck "${shell_files[@]}"

log "YAML lint"
run_yamllint

log "Compose config validation"
ENV_NAME=ci \
MODEL_NAME=Qwen/Qwen3.5-2B \
MAX_MODEL_LEN=4096 \
GPU_MEMORY_UTILIZATION=0.90 \
NGINX_HTTPS_HOST_PORT=443 \
"${COMPOSE_CMD[@]}" -f docker/docker-compose-vllm-nginx.yml config -q

log "Build nginx test image (${IMAGE_TAG})"
"${ENGINE}" build -f docker/nginx/Dockerfile -t "${IMAGE_TAG}" .

log "Validate nginx rendered config"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

openssl req -x509 -nodes -newkey rsa:2048 -days 1 \
  -keyout "${tmp_dir}/server.key" \
  -out "${tmp_dir}/server.crt" \
  -subj "/CN=localhost" >/dev/null 2>&1
cp "${tmp_dir}/server.crt" "${tmp_dir}/server_fullchain.crt"
printf '%s' 'dummy-key' > "${tmp_dir}/vllm_api_key"

# shellcheck disable=SC2016
"${ENGINE}" run --rm \
  -e NGINX_BACKEND_UPSTREAM=127.0.0.1:8000 \
  -e NGINX_HTTPS_LISTEN_PORT=443 \
  -e NGINX_API_KEY=dummy-key \
  -v "${tmp_dir}/server.crt:/etc/nginx/certs/server.crt:ro" \
  -v "${tmp_dir}/server.key:/etc/nginx/certs/server.key:ro" \
  -v "${tmp_dir}/server_fullchain.crt:/etc/nginx/certs/server_fullchain.crt:ro" \
  --entrypoint sh \
  "${IMAGE_TAG}" \
  -lc 'envsubst '\''${NGINX_BACKEND_UPSTREAM} ${NGINX_HTTPS_LISTEN_PORT} ${NGINX_API_KEY}'\'' < /etc/nginx/templates/nginx.conf.template > /tmp/nginx.conf && nginx -t -c /tmp/nginx.conf'

if [[ "${CLEANUP_IMAGES}" -eq 1 ]]; then
  cleanup_old_ci_images "${IMAGE_TAG}"
else
  log "Skipping ci-local image cleanup (--no-cleanup-images)"
fi

log "All checks passed. No running service was stopped or redeployed."