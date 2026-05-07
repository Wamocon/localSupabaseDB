#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG_FILE="${REPO_ROOT}/supabase/config.toml"
TEMPLATE_FILE="${REPO_ROOT}/supabase/config.toml.template"

# Lokale Supabase-CLI (aus npm install) bevorzugen, um Konflikte mit globalem Install zu vermeiden
if [[ -d "${REPO_ROOT}/node_modules/.bin" ]]; then
  export PATH="${REPO_ROOT}/node_modules/.bin:${PATH}"
fi
PORTS_FILE="${REPO_ROOT}/.ports"
TARGET_DIR="${PWD}"
TARGET_ENV_FILE="${TARGET_DIR}/.env.local"
TARGET_ENV_BACKUP="${TARGET_DIR}/.env.local.backup"
project_id=""

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

read_project_id_from_config() {
  local val
  val="$(grep '^project_id' "${CONFIG_FILE}" 2>/dev/null | sed 's/project_id *= *"\(.*\)"/\1/' | tail -n1)"
  printf "%s" "${val:-localSupabaseDB}"
}

set_project_id() {
  local app_name="$1"
  # Sanitize: lowercase, only alphanumeric and hyphens, max 40 chars
  local sanitized
  sanitized="$(printf "%s" "${app_name}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9-]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//' \
    | cut -c1-40)"

  if [ -z "${sanitized}" ]; then
    log_error "Invalid app name: '${app_name}'. Use letters, numbers and hyphens only."
    return 1
  fi

  project_id="${sanitized}"
  sed -E -i.bak "s/^project_id = \".*\"/project_id = \"${project_id}\"/" "${CONFIG_FILE}"
  rm -f "${CONFIG_FILE}.bak"
  cov_hit "setup_project_id_set"
  log_info "App: ${project_id}"
}

check_existing_volume() {
  local vol_name="supabase_db_${project_id}"
  if docker volume ls --format '{{.Name}}' 2>/dev/null | grep -qx "${vol_name}"; then
    cov_hit "setup_volume_exists"
    log_info "Existing data found for '${project_id}' → resuming."
  else
    cov_hit "setup_volume_new"
    log_info "No existing data for '${project_id}' → starting fresh."
  fi
}

reset_volume() {
  log_warn "Resetting data for app '${project_id}'..."
  # Stop first to avoid conflicts
  cd "${REPO_ROOT}" && supabase stop --no-backup 2>&1 || true
  local vol_name="supabase_db_${project_id}"
  docker volume rm -f "${vol_name}" >/dev/null 2>&1 || true
  cov_hit "setup_volume_reset"
  log_info "Data reset done."
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

  if command -v netstat >/dev/null 2>&1; then
    if netstat -an 2>/dev/null | grep -qE "[:.]${port}[[:space:]].*LISTEN"; then
      cov_hit "setup_port_netstat_busy"
      return 1
    fi
    cov_hit "setup_port_netstat_free"
    return 0
  fi

  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | grep -q ":${port}[[:space:]]"; then
      cov_hit "setup_port_ss_busy"
      return 1
    fi
    cov_hit "setup_port_ss_free"
    return 0
  fi

  cov_hit "setup_port_no_tool"
  log_warn "No port-checking tool found (lsof/nc/netstat/ss). Assuming ports are free."
  return 0
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

  # Note: supabase --version exits with code 1 on Windows when an update is available.
  # We only check if the binary is callable, not the exit code.
  if ! supabase --version >/dev/null 2>&1; then
    # Try once more without stderr redirect – some versions write only to stdout
    if ! supabase --version 2>/dev/null | grep -q '[0-9]'; then
      cov_hit "setup_prereq_supabase_broken"
      log_error "Supabase CLI is installed but not working correctly."
      return 1
    fi
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

parse_status_output() {
  local output="$1"

  # Old CLI format: "  API URL: http://..."
  local val
  val="$(printf "%s\n" "${output}" | sed -n 's/^ *API URL: *//p' | tail -n1)"
  [ -n "${val}" ] && api_url="${val}"

  # New CLI format (table): "│ Project URL    │ http://... │"
  if [ -z "${api_url}" ]; then
    val="$(printf "%s\n" "${output}" | grep -i 'Project URL' | sed 's/^[^│]*│[^│]*│[[:space:]]*//' | sed 's/[[:space:]]*│.*$//' | tail -n1)"
    [ -n "${val}" ] && api_url="${val}"
  fi

  # Old CLI format: "  anon key: eyJh..."
  val="$(printf "%s\n" "${output}" | sed -n 's/^ *anon key: *//p' | tail -n1)"
  [ -n "${val}" ] && anon_key="${val}"

  # New CLI format: "│ Publishable │ sb_publishable_... │"
  if [ -z "${anon_key}" ]; then
    val="$(printf "%s\n" "${output}" | grep -i 'Publishable' | sed 's/^[^│]*│[^│]*│[[:space:]]*//' | sed 's/[[:space:]]*│.*$//' | tail -n1)"
    [ -n "${val}" ] && anon_key="${val}"
  fi

  # Old CLI format: "  service_role key: eyJh..."
  val="$(printf "%s\n" "${output}" | sed -n 's/^ *service_role key: *//p' | tail -n1)"
  [ -n "${val}" ] && service_role_key="${val}"

  # New CLI format: "│ Secret      │ sb_secret_... │"
  if [ -z "${service_role_key}" ]; then
    val="$(printf "%s\n" "${output}" | grep -i '│[[:space:]]*Secret' | sed 's/^[^│]*│[^│]*│[[:space:]]*//' | sed 's/[[:space:]]*│.*$//' | tail -n1)"
    [ -n "${val}" ] && service_role_key="${val}"
  fi
}

extract_values_from_output() {
  local start_output="$1"

  api_url=""
  anon_key=""
  service_role_key=""

  parse_status_output "${start_output}"

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
    parse_status_output "${status_output}"
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
  local app_name=""
  local do_reset=0
  local target_dir_arg=""

  while [ $# -gt 0 ]; do
    case "$1" in
      --app)
        app_name="${2:-}"
        shift 2
        ;;
      --reset)
        do_reset=1
        shift
        ;;
      *)
        target_dir_arg="$1"
        shift
        ;;
    esac
  done

  configure_target_dir "${target_dir_arg}"

  # config.toml aus Template erstellen wenn nicht vorhanden (nach git clone / purge)
  if [[ ! -f "${CONFIG_FILE}" ]]; then
    if [[ ! -f "${TEMPLATE_FILE}" ]]; then
      log_error "Weder config.toml noch config.toml.template gefunden. Repository beschaedigt?"
      return 1
    fi
    cp "${TEMPLATE_FILE}" "${CONFIG_FILE}"
    log_info "config.toml aus Template erstellt."
  fi

  check_prerequisites || return 1

  if [ -n "${app_name}" ]; then
    set_project_id "${app_name}" || return 1
  else
    project_id="$(read_project_id_from_config)"
    log_info "App: ${project_id} (from config.toml)"
  fi

  if [ "${do_reset}" -eq 1 ]; then
    reset_volume
  fi

  check_existing_volume
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
  main "$@"
fi
