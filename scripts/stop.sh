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

cov_hit() {
  if [ -n "${COVERAGE_FILE:-}" ]; then
    printf '%s\n' "$1" >> "${COVERAGE_FILE}"
  fi
}

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
  cov_hit "stop_patch_config"
}

sync_ports_if_available() {
  if [ ! -f "${PORTS_FILE}" ]; then
    cov_hit "stop_ports_missing"
    log_warn "No .ports file found at ${PORTS_FILE}. Stopping default instance configuration."
    return 0
  fi

  cov_hit "stop_ports_present"
  log_info "Using port mapping from ${PORTS_FILE}"
  # shellcheck disable=SC1090
  source "${PORTS_FILE}"
  apply_ports_to_config "${API_PORT}" "${DB_PORT}" "${STUDIO_PORT}" "${INBUCKET_PORT}"
}

check_supabase_cli() {
  if ! command -v supabase >/dev/null 2>&1; then
    cov_hit "stop_supabase_missing"
    log_error "Supabase CLI is not installed."
    return 1
  fi

  cov_hit "stop_supabase_ok"
  return 0
}

get_project_id() {
  local val
  val="$(grep '^project_id' "${CONFIG_FILE}" 2>/dev/null | sed 's/project_id *= *"\(.*\)"/\1/' | tail -n1)"
  printf "%s" "${val:-localSupabaseDB}"
}

force_remove_containers() {
  local proj_id
  proj_id="$(get_project_id)"
  log_warn "Forcing removal of leftover Supabase containers for: ${proj_id}..."
  local containers
  containers="$(docker ps -aq --filter "name=${proj_id}" 2>/dev/null || true)"
  if [ -n "${containers}" ]; then
    # shellcheck disable=SC2086
    docker rm -f ${containers} >/dev/null 2>&1 || true
    cov_hit "stop_force_remove"
    log_warn "Leftover containers removed."
  else
    cov_hit "stop_no_leftovers"
  fi
}

stop_instance() {
  if cd "${REPO_ROOT}" && supabase stop 2>&1; then
    cov_hit "stop_run_ok"
    log_info "Supabase stopped successfully."
    force_remove_containers
    return 0
  fi

  cov_hit "stop_run_fail"
  log_warn "supabase stop reported an error. Attempting forced container cleanup..."
  force_remove_containers
  return 0
}

main() {
  sync_ports_if_available
  check_supabase_cli || return 1
  stop_instance || return 1
  cov_hit "stop_main_ok"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
