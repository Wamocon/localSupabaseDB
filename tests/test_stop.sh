#!/usr/bin/env bash
set -euo pipefail

# REPO_ROOT: In CI über $GITHUB_WORKSPACE gesetzt, lokal relativ zur Skript-Position ermittelt.
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/lib.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/stop.sh"

# Hilfsfunktion: config.toml für Tests bereitstellen (Template als Fallback)
_get_test_config() {
  local dest="$1"
  if [ -f "${REPO_ROOT}/supabase/config.toml" ]; then
    cp "${REPO_ROOT}/supabase/config.toml" "${dest}"
  else
    cp "${REPO_ROOT}/supabase/config.toml.template" "${dest}"
  fi
}

run_test_apply_ports() {
  local tmp cfg
  tmp="$(new_temp_dir)"
  cfg="${tmp}/config.toml"
  _get_test_config "${cfg}"
  CONFIG_FILE="${cfg}"

  apply_ports_to_config 55101 55102 55103 55104
  assert_file_contains "${cfg}" "port = 55101" "stop api patch"
  assert_file_contains "${cfg}" "port = 55104" "stop inbucket patch"
  pass "stop: apply_ports"
}

run_test_sync_ports() {
  local tmp cfg ports
  tmp="$(new_temp_dir)"
  cfg="${tmp}/config.toml"
  ports="${tmp}/.ports"
  _get_test_config "${cfg}"
  CONFIG_FILE="${cfg}"
  PORTS_FILE="${ports}"

  assert_success "sync without ports" sync_ports_if_available

  cat > "${ports}" <<EOP
API_PORT=55201
DB_PORT=55202
STUDIO_PORT=55203
INBUCKET_PORT=55204
EOP
  assert_success "sync with ports" sync_ports_if_available
  assert_file_contains "${cfg}" "port = 55201" "sync port patched"
  pass "stop: sync_ports"
}

run_test_cli_and_stop() {
  local tmp stubbin old_path old_repo old_cfg
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"
  old_repo="${REPO_ROOT}"
  old_cfg="${CONFIG_FILE}"

  _get_test_config "${tmp}/config.toml"
  CONFIG_FILE="${tmp}/config.toml"

  PATH="${stubbin}"
  assert_failure "stop cli missing" check_supabase_cli

  PATH="${old_path}"
  write_stub "${stubbin}/supabase" 'if [ "$1" = "stop" ]; then if [ "${SUPABASE_STOP_FAIL:-0}" = "1" ]; then exit 1; fi; exit 0; fi; exit 0'
  write_stub "${stubbin}/docker" 'if [ "$1" = "ps" ]; then printf ""; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  assert_success "stop cli ok" check_supabase_cli

  REPO_ROOT="${tmp}"
  SUPABASE_STOP_FAIL=1 assert_failure "stop instance fail" stop_instance
  SUPABASE_STOP_FAIL=0 assert_success "stop instance ok" stop_instance

  REPO_ROOT="${old_repo}"
  CONFIG_FILE="${old_cfg}"
  PATH="${old_path}"
  pass "stop: cli_and_stop"
}

run_test_main() {
  local tmp stubbin old_path cfg ports old_repo
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  cfg="${tmp}/config.toml"
  ports="${tmp}/.ports"
  old_repo="${REPO_ROOT}"

  _get_test_config "${cfg}"
  cat > "${ports}" <<EOP
API_PORT=55301
DB_PORT=55302
STUDIO_PORT=55303
INBUCKET_PORT=55304
EOP

  CONFIG_FILE="${cfg}"
  PORTS_FILE="${ports}"
  REPO_ROOT="${tmp}"

  old_path="${PATH}"
  write_stub "${stubbin}/supabase" 'if [ "$1" = "stop" ]; then exit 0; fi; exit 0'
  write_stub "${stubbin}/docker" 'if [ "$1" = "ps" ]; then printf ""; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  assert_success "stop main success" main

  REPO_ROOT="${old_repo}"
  PATH="${old_path}"
  pass "stop: main"
}

# ── Neue ausführliche Tests ────────────────────────────────────────────────────

run_test_force_remove_containers() {
  local tmp stubbin old_path old_cfg old_repo
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"
  old_cfg="${CONFIG_FILE}"
  old_repo="${REPO_ROOT}"

  _get_test_config "${tmp}/config.toml"
  CONFIG_FILE="${tmp}/config.toml"
  REPO_ROOT="${tmp}"

  # Fall 1: Container vorhanden → stop_force_remove
  write_stub "${stubbin}/docker" '
if [ "$1" = "ps" ]; then printf "abc123\ndef456\n"; exit 0; fi
if [ "$1" = "rm" ]; then exit 0; fi
exit 0'
  PATH="${stubbin}:${old_path}"
  assert_success "force_remove mit Containern" force_remove_containers

  # Fall 2: Keine Container → stop_no_leftovers
  write_stub "${stubbin}/docker" '
if [ "$1" = "ps" ]; then printf ""; exit 0; fi
exit 0'
  assert_success "force_remove ohne Container" force_remove_containers

  CONFIG_FILE="${old_cfg}"
  REPO_ROOT="${old_repo}"
  PATH="${old_path}"
  pass "stop: force_remove_containers"
}

run_test_get_project_id() {
  local tmp old_cfg
  tmp="$(new_temp_dir)"
  old_cfg="${CONFIG_FILE}"

  _get_test_config "${tmp}/config.toml"
  CONFIG_FILE="${tmp}/config.toml"

  local pid
  pid="$(get_project_id)"
  assert_not_empty "${pid}" "get_project_id gibt Wert zurück"

  # Fallback: Datei ohne project_id → "localSupabaseDB"
  printf '[api]\nport = 54321\n' > "${tmp}/empty.toml"
  CONFIG_FILE="${tmp}/empty.toml"
  pid="$(get_project_id)"
  assert_eq "localSupabaseDB" "${pid}" "get_project_id Fallback"

  CONFIG_FILE="${old_cfg}"
  pass "stop: get_project_id"
}

run_test_main_stop_fail() {
  local tmp stubbin old_path old_cfg old_ports old_repo
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"
  old_cfg="${CONFIG_FILE}"
  old_ports="${PORTS_FILE}"
  old_repo="${REPO_ROOT}"

  _get_test_config "${tmp}/config.toml"
  cat > "${tmp}/.ports" <<EOP
API_PORT=55801
DB_PORT=55802
STUDIO_PORT=55803
INBUCKET_PORT=55804
EOP

  CONFIG_FILE="${tmp}/config.toml"
  PORTS_FILE="${tmp}/.ports"
  REPO_ROOT="${tmp}"

  write_stub "${stubbin}/supabase" 'if [ "$1" = "stop" ]; then exit 1; fi; exit 0'
  write_stub "${stubbin}/docker" 'if [ "$1" = "ps" ]; then printf ""; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  assert_failure "stop main schlägt fehl" main

  CONFIG_FILE="${old_cfg}"
  PORTS_FILE="${old_ports}"
  REPO_ROOT="${old_repo}"
  PATH="${old_path}"
  pass "stop: main_fail"
}

run_test_apply_ports
run_test_sync_ports
run_test_cli_and_stop
run_test_main
run_test_force_remove_containers
run_test_get_project_id
run_test_main_stop_fail

pass "stop tests complete"
