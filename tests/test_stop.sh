#!/usr/bin/env bash
set -euo pipefail

TEST_REPO_ROOT="/home/runner/work/localSupabaseDB/localSupabaseDB"
# shellcheck disable=SC1091
source "${TEST_REPO_ROOT}/tests/lib.sh"
# shellcheck disable=SC1091
source "${TEST_REPO_ROOT}/scripts/stop.sh"

run_test_apply_ports() {
  local tmp cfg
  tmp="$(new_temp_dir)"
  cfg="${tmp}/config.toml"
  cp "${TEST_REPO_ROOT}/supabase/config.toml" "${cfg}"
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
  cp "${TEST_REPO_ROOT}/supabase/config.toml" "${cfg}"
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
  local tmp stubbin old_path
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"

  PATH="${stubbin}"
  assert_failure "stop cli missing" check_supabase_cli

  PATH="${old_path}"
  write_stub "${stubbin}/supabase" 'if [ "$1" = "stop" ]; then if [ "${SUPABASE_STOP_FAIL:-0}" = "1" ]; then exit 1; fi; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  assert_success "stop cli ok" check_supabase_cli

  REPO_ROOT="${tmp}"
  SUPABASE_STOP_FAIL=1 assert_failure "stop instance fail" stop_instance
  SUPABASE_STOP_FAIL=0 assert_success "stop instance ok" stop_instance

  PATH="${old_path}"
  pass "stop: cli_and_stop"
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
  PATH="${stubbin}:${old_path}"

  assert_success "stop main success" main

  PATH="${old_path}"
  pass "stop: main"
}

run_test_apply_ports
run_test_sync_ports
run_test_cli_and_stop
run_test_main

pass "stop tests complete"
