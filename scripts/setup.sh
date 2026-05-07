#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/supabase/config.toml"
PORTS_FILE="${REPO_ROOT}/.ports"
TARGET_DIR="${PWD}"
TARGET_ENV_FILE="${TARGET_DIR}/.env.local"
TARGET_ENV_BACKUP="${TARGET_DIR}/.env.local.backup"

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

configure_target_dir() {
  local input_dir="${1:-}"

  if [ -n "${input_dir}" ]; then
    TARGET_DIR="$(cd "${input_dir}" && pwd)"
    cov_hit "setup_target_arg"
  else
    TARGET_DIR="${PWD}"
    cov_hit "setup_target_pwd"
  fi

  TARGET_ENV_FILE="${TARGET_DIR}/.env.local"
  TARGET_ENV_BACKUP="${TARGET_DIR}/.env.local.backup"
}

is_port_free() {
  local port="$1"

  if command -v lsof >/dev/null 2>&1; then
    if lsof -iTCP:"${port}" -sTCP:LISTEN -Pn >/dev/null 2>&1; then
      cov_hit "setup_port_lsof_busy"
      return 1
    fi
    cov_hit "setup_port_lsof_free"
    return 0
  fi

  if command -v nc >/dev/null 2>&1; then
    if nc -z 127.0.0.1 "${port}" >/dev/null 2>&1; then
      cov_hit "setup_port_nc_busy"
      return 1
    fi
    cov_hit "setup_port_nc_free"
    return 0
  fi

  cov_hit "setup_port_no_tool"
  log_error "Neither 'lsof' nor 'nc' is available to check ports."
  exit 1
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
  cov_hit "setup_patch_config"
}

check_prerequisites() {
  log_info "Checking prerequisites..."

  if ! docker info >/dev/null 2>&1; then
    cov_hit "setup_prereq_docker_fail"
    log_error "Docker is not running. Please start Docker Desktop and retry."
    return 1
  fi
  cov_hit "setup_prereq_docker_ok"

  if ! command -v supabase >/dev/null 2>&1; then
    cov_hit "setup_prereq_supabase_missing"
    log_error "Supabase CLI is not installed."
    log_warn "Install with: brew install supabase/tap/supabase"
    log_warn "or: npm install supabase --save-dev"
    return 1
  fi

  if ! supabase --version >/dev/null 2>&1; then
    cov_hit "setup_prereq_supabase_broken"
    log_error "Supabase CLI is installed but not working correctly."
    return 1
  fi

  cov_hit "setup_prereq_ok"
  return 0
}

select_port_block() {
  local base=54321
  local max_port_offset=980
  local selected=0
  local offset

  log_info "Selecting free port block..."

  for offset in 0 $(seq 10 10 "${max_port_offset}"); do
    api_port=$((base + offset))
    db_port=$((api_port + 1))
    studio_port=$((api_port + 2))
    inbucket_port=$((api_port + 3))

    if is_port_free "${api_port}" && is_port_free "${db_port}" && is_port_free "${studio_port}" && is_port_free "${inbucket_port}"; then
      selected=1
      cov_hit "setup_port_block_selected"
      break
    fi
  done

  if [ "${selected}" -ne 1 ]; then
    cov_hit "setup_port_block_fail"
    log_error "No free port block found from 54321 upwards."
    return 1
  fi

  cov_hit "setup_port_block_ok"
  return 0
}

write_ports_file() {
  cat > "${PORTS_FILE}" <<EOP
API_PORT=${api_port}
DB_PORT=${db_port}
STUDIO_PORT=${studio_port}
INBUCKET_PORT=${inbucket_port}
EOP
  cov_hit "setup_ports_file_written"
}

extract_values_from_output() {
  local start_output="$1"

  api_url="$(printf "%s\n" "${start_output}" | sed -n 's/^ *API URL: *//p' | tail -n1)"
  anon_key="$(printf "%s\n" "${start_output}" | sed -n 's/^ *anon key: *//p' | tail -n1)"
  service_role_key="$(printf "%s\n" "${start_output}" | sed -n 's/^ *service_role key: *//p' | tail -n1)"

  if [ -z "${api_url}" ]; then
    api_url="http://127.0.0.1:${api_port}"
    cov_hit "setup_parse_api_fallback"
  else
    cov_hit "setup_parse_api_from_start"
  fi

  if [ -z "${anon_key}" ] || [ -z "${service_role_key}" ]; then
    cov_hit "setup_parse_key_fallback"
    log_warn "Could not parse keys from start output. Falling back to 'supabase status'."
    status_output="$(cd "${REPO_ROOT}" && supabase status 2>&1 || true)"
    anon_key="${anon_key:-$(printf "%s\n" "${status_output}" | sed -n 's/^ *anon key: *//p' | tail -n1)}"
    service_role_key="${service_role_key:-$(printf "%s\n" "${status_output}" | sed -n 's/^ *service_role key: *//p' | tail -n1)}"
  else
    cov_hit "setup_parse_key_from_start"
  fi

  if [ -z "${anon_key}" ] || [ -z "${service_role_key}" ]; then
    cov_hit "setup_parse_key_fail"
    log_error "Could not determine anon/service role keys."
    return 1
  fi

  cov_hit "setup_parse_key_ok"
  return 0
}

start_supabase() {
  log_info "Starting Supabase..."
  if ! start_output="$(cd "${REPO_ROOT}" && supabase start 2>&1)"; then
    cov_hit "setup_start_fail"
    log_error "supabase start failed"
    printf "%s\n" "${start_output}" >&2
    return 1
  fi

  cov_hit "setup_start_ok"
  extract_values_from_output "${start_output}"
}

write_env_file() {
  if [ -f "${TARGET_ENV_FILE}" ]; then
    cp "${TARGET_ENV_FILE}" "${TARGET_ENV_BACKUP}"
    cov_hit "setup_env_backup"
    log_warn "Existing .env.local backed up to ${TARGET_ENV_BACKUP}"
  else
    cov_hit "setup_env_no_backup"
  fi

  cat > "${TARGET_ENV_FILE}" <<EOF_ENV
# Generated by scripts/setup.sh
# For Supabase Cloud, replace these values with your cloud project values.
NEXT_PUBLIC_SUPABASE_URL=${api_url}
NEXT_PUBLIC_SUPABASE_ANON_KEY=${anon_key}
SUPABASE_SERVICE_ROLE_KEY=${service_role_key}
EOF_ENV

  cov_hit "setup_env_written"
  log_info "Created ${TARGET_ENV_FILE}"
}

print_summary() {
  printf "\n"
  log_info "Setup complete"
  printf -- "- API URL: %s\n" "${api_url}"
  printf -- "- Studio URL: %s\n" "http://127.0.0.1:${studio_port}"
  printf -- "- Inbucket URL: %s\n" "http://127.0.0.1:${inbucket_port}"
  printf -- "- Port config: %s\n" "${PORTS_FILE}"
  printf "\nNext steps:\n"
  printf "1) Update 'site_url' in %s to your Next.js app URL.\n" "${CONFIG_FILE}"
  printf "2) Start your Next.js app and use %s.\n" "${TARGET_ENV_FILE}"
  cov_hit "setup_summary"
}

main() {
  configure_target_dir "${1:-}"
  check_prerequisites || return 1
  select_port_block || return 1
  write_ports_file
  apply_ports_to_config "${api_port}" "${db_port}" "${studio_port}" "${inbucket_port}"
  log_info "Using ports: API=${api_port}, DB=${db_port}, Studio=${studio_port}, Inbucket=${inbucket_port}"
  start_supabase || return 1
  write_env_file
  print_summary
  cov_hit "setup_main_ok"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "${1:-}"
fi
