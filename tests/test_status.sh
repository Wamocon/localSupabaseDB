#!/usr/bin/env bash
set -euo pipefail

TEST_REPO_ROOT="/home/runner/work/localSupabaseDB/localSupabaseDB"
# shellcheck disable=SC1091
source "${TEST_REPO_ROOT}/tests/lib.sh"
# shellcheck disable=SC1091
source "${TEST_REPO_ROOT}/scripts/status.sh"

run_test_apply_ports_and_sync() {
  local tmp cfg ports
  tmp="$(new_temp_dir)"
  cfg="${tmp}/config.toml"
  ports="${tmp}/.ports"
  cp "${TEST_REPO_ROOT}/supabase/config.toml" "${cfg}"
  CONFIG_FILE="${cfg}"
  PORTS_FILE="${ports}"

  apply_ports_to_config 55401 55402 55403 55404
  assert_file_contains "${cfg}" "port = 55401" "status api patch"

  assert_success "status sync missing ports" sync_ports_if_available

  cat > "${ports}" <<EOP
API_PORT=55411
DB_PORT=55412
STUDIO_PORT=55413
INBUCKET_PORT=55414
EOP
  assert_success "status sync with ports" sync_ports_if_available
  assert_file_contains "${cfg}" "port = 55411" "status sync patched"

  pass "status: apply/sync"
}

run_test_cli_fetch_validate() {
  local tmp stubbin old_path
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"

  PATH="${stubbin}"
  assert_failure "status cli missing" check_supabase_cli

  PATH="${old_path}"
  write_stub "${stubbin}/supabase" 'if [ "$1" = "status" ]; then if [ "${STATUS_NOT_RUNNING:-0}" = "1" ]; then printf "stopped\n"; else printf "API URL: http://127.0.0.1:54321\n"; fi; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  assert_success "status cli ok" check_supabase_cli

  REPO_ROOT="${tmp}"
  assert_success "status fetch" fetch_status

  status_output="stopped"
  assert_failure "status validate not running" validate_status_output

  status_output="API URL: http://127.0.0.1:54321"
  assert_success "status validate running" validate_status_output

  assert_success "status print" print_status

  PATH="${old_path}"
  pass "status: cli/fetch/validate"
}

run_test_main() {
  local tmp stubbin old_path cfg ports
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  cfg="${tmp}/config.toml"
  ports="${tmp}/.ports"
  cp "${TEST_REPO_ROOT}/supabase/config.toml" "${cfg}"

  cat > "${ports}" <<EOP
API_PORT=55521
DB_PORT=55522
STUDIO_PORT=55523
INBUCKET_PORT=55524
EOP

  CONFIG_FILE="${cfg}"
  PORTS_FILE="${ports}"
  REPO_ROOT="${tmp}"

  old_path="${PATH}"
  write_stub "${stubbin}/supabase" 'if [ "$1" = "status" ]; then printf "API URL: http://127.0.0.1:55521\n"; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  assert_success "status main success" main

  PATH="${old_path}"
  pass "status: main"
}

run_test_apply_ports_and_sync
run_test_cli_fetch_validate
run_test_main

pass "status tests complete"
