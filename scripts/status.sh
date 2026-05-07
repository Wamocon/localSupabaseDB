#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PORTS_FILE="${REPO_ROOT}/.ports"
CONFIG_FILE="${REPO_ROOT}/supabase/config.toml"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
  printf "%b%s%b\n" "${GREEN}" "$1" "${NC}"
}

log_warn() {
  printf "%b%s%b\n" "${YELLOW}" "$1" "${NC}"
}

log_error() {
  printf "%b%s%b\n" "${RED}" "$1" "${NC}" >&2
}

apply_ports_to_config() {
  local api_port="$1"
  local db_port="$2"
  local studio_port="$3"
  local inbucket_port="$4"

  sed -E -i.bak \
    -e "/^\\[api\\]/,/^\\[/{s/^port = [0-9]+$/port = ${api_port}/}" \
    -e "/^\\[db\\]/,/^\\[/{s/^port = [0-9]+$/port = ${db_port}/}" \
    -e "/^\\[studio\\]/,/^\\[/{s/^port = [0-9]+$/port = ${studio_port}/}" \
    -e "/^\\[inbucket\\]/,/^\\[/{s/^port = [0-9]+$/port = ${inbucket_port}/}" \
    "${CONFIG_FILE}"

  rm -f "${CONFIG_FILE}.bak"
}

if [ -f "${PORTS_FILE}" ]; then
  log_info "Configured ports (.ports):"
  cat "${PORTS_FILE}"
  # shellcheck disable=SC1090
  source "${PORTS_FILE}"
  apply_ports_to_config "${API_PORT}" "${DB_PORT}" "${STUDIO_PORT}" "${INBUCKET_PORT}"
else
  log_warn "No .ports file found. Run ./scripts/setup.sh to initialize ports."
fi

if ! command -v supabase >/dev/null 2>&1; then
  log_error "Supabase CLI is not installed."
  exit 1
fi

status_output="$(cd "${REPO_ROOT}" && supabase status 2>&1 || true)"

if printf "%s\n" "${status_output}" | grep -qi "stopped\|not running\|cannot find"; then
  log_error "Supabase instance does not appear to be running."
  printf "%s\n" "${status_output}"
  exit 1
fi

log_info "Current Supabase status:"
printf "%s\n" "${status_output}"
