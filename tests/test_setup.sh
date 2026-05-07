#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/home/runner/work/localSupabaseDB/localSupabaseDB"
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/lib.sh"
# shellcheck disable=SC1091
source "${REPO_ROOT}/scripts/setup.sh"

run_test_setup_target_dir() {
  local tmp
  tmp="$(new_temp_dir)"
  configure_target_dir ""
  assert_eq "${PWD}" "${TARGET_DIR}" "configure_target_dir ohne Argument"

  configure_target_dir "${tmp}"
  assert_eq "${tmp}" "${TARGET_DIR}" "configure_target_dir mit Argument"
  pass "setup: target dir"
}

run_test_is_port_free_branches() {
  local tmp stubbin old_path
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"

  write_stub "${stubbin}/lsof" 'if [ "${LSOF_BUSY:-0}" = "1" ]; then exit 0; fi; exit 1'
  old_path="${PATH}"
  PATH="${stubbin}:${PATH}"

  LSOF_BUSY=1 assert_failure "is_port_free lsof busy" is_port_free 55555
  LSOF_BUSY=0 assert_success "is_port_free lsof free" is_port_free 55555

  rm -f "${stubbin}/lsof"
  write_stub "${stubbin}/nc" 'if [ "${NC_BUSY:-0}" = "1" ]; then exit 0; fi; exit 1'
  PATH="${stubbin}:${old_path}"
  command() {
    if [ "$1" = "-v" ] && [ "$2" = "lsof" ]; then
      return 1
    fi
    builtin command "$@"
  }
  NC_BUSY=1 assert_failure "is_port_free nc busy" is_port_free 55556
  NC_BUSY=0 assert_success "is_port_free nc free" is_port_free 55556

  # netstat branch: busy
  rm -f "${stubbin}/nc"
  write_stub "${stubbin}/netstat" 'if [ "${NETSTAT_BUSY:-0}" = "1" ]; then printf "TCP  0.0.0.0:55557  LISTEN\n"; else printf ""; fi; exit 0'
  command() {
    if [ "$1" = "-v" ] && { [ "$2" = "lsof" ] || [ "$2" = "nc" ]; }; then
      return 1
    fi
    builtin command "$@"
  }
  NETSTAT_BUSY=1 assert_failure "is_port_free netstat busy" is_port_free 55557
  NETSTAT_BUSY=0 assert_success "is_port_free netstat free" is_port_free 55557

  # ss branch: busy
  rm -f "${stubbin}/netstat"
  write_stub "${stubbin}/ss" 'if [ "${SS_BUSY:-0}" = "1" ]; then printf "LISTEN 0 128 0.0.0.0:55558 0.0.0.0:*\n"; else printf ""; fi; exit 0'
  command() {
    if [ "$1" = "-v" ] && { [ "$2" = "lsof" ] || [ "$2" = "nc" ] || [ "$2" = "netstat" ]; }; then
      return 1
    fi
    builtin command "$@"
  }
  SS_BUSY=1 assert_failure "is_port_free ss busy" is_port_free 55558
  SS_BUSY=0 assert_success "is_port_free ss free" is_port_free 55558

  # no tool: should now warn and return 0 (free assumed)
  rm -f "${stubbin}/ss"
  command() {
    if [ "$1" = "-v" ] && { [ "$2" = "lsof" ] || [ "$2" = "nc" ] || [ "$2" = "netstat" ] || [ "$2" = "ss" ]; }; then
      return 1
    fi
    builtin command "$@"
  }
  assert_success "is_port_free no tool: assumes free" is_port_free 55559
  unset -f command

  PATH="${old_path}"
  pass "setup: is_port_free branches"
}

run_test_apply_ports_to_config() {
  local tmp cfg
  tmp="$(new_temp_dir)"
  cfg="${tmp}/config.toml"
  cp "${REPO_ROOT}/supabase/config.toml" "${cfg}"
  CONFIG_FILE="${cfg}"

  apply_ports_to_config 55001 55002 55003 55004
  assert_file_contains "${cfg}" "port = 55001" "api port gepatcht"
  assert_file_contains "${cfg}" "port = 55002" "db port gepatcht"
  assert_file_contains "${cfg}" "port = 55003" "studio port gepatcht"
  assert_file_contains "${cfg}" "port = 55004" "inbucket port gepatcht"
  pass "setup: apply_ports_to_config"
}

run_test_check_prerequisites_branches() {
  local tmp stubbin old_path
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"

  write_stub "${stubbin}/docker" 'exit 1'
  PATH="${stubbin}:${old_path}"
  hash -r 2>/dev/null || true
  assert_failure "prereq docker fail" check_prerequisites

  write_stub "${stubbin}/docker" 'exit 0'
  rm -f "${stubbin}/supabase"
  # Minimales PATH: nur stubbin, damit weder node_modules/.bin noch
  # system-supabase (auf ubuntu-latest vorinstalliert) gefunden werden.
  # command -v supabase darf NICHT erfolgreich sein fuer diesen Test.
  PATH="${stubbin}"
  hash -r 2>/dev/null || true
  assert_failure "prereq supabase missing" check_prerequisites

  # Volles PATH wiederherstellen fuer folgende Tests (supabase stub vorhanden)
  PATH="${stubbin}:${old_path}"
  write_stub "${stubbin}/supabase" 'if [ "$1" = "--version" ]; then exit 1; fi; exit 0'
  hash -r 2>/dev/null || true
  assert_failure "prereq supabase broken" check_prerequisites

  write_stub "${stubbin}/supabase" 'if [ "$1" = "--version" ]; then echo "2.0.0"; exit 0; fi; exit 0'
  hash -r 2>/dev/null || true
  assert_success "prereq success" check_prerequisites

  PATH="${old_path}"
  pass "setup: check_prerequisites branches"
}

run_test_select_port_block_branches() {
  local counter
  counter=0
  is_port_free() {
    counter=$((counter + 1))
    if [ "${counter}" -le 1 ]; then
      return 1
    fi
    return 0
  }
  assert_success "select_port_block second block" select_port_block
  assert_eq "54331" "${api_port}" "api port second block"

  is_port_free() { return 1; }
  assert_failure "select_port_block fail" select_port_block
  pass "setup: select_port_block branches"
}

run_test_extract_values_branches() {
  local tmp stubbin old_path sample_output
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"

  write_stub "${stubbin}/supabase" 'if [ "$1" = "status" ]; then printf "anon key: status-anon\nservice_role key: status-service\n"; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  api_port=54321
  sample_output=$'API URL: http://127.0.0.1:54321\nanon key: start-anon\nservice_role key: start-service'
  assert_success "extract from start output" extract_values_from_output "${sample_output}"
  assert_eq "http://127.0.0.1:54321" "${api_url}" "api_url parse"
  assert_eq "start-anon" "${anon_key}" "anon parse"
  assert_eq "start-service" "${service_role_key}" "service parse"

  sample_output=$'Some other output'
  assert_success "extract fallback to status" extract_values_from_output "${sample_output}"
  assert_eq "http://127.0.0.1:54321" "${api_url}" "api fallback"
  assert_eq "status-anon" "${anon_key}" "anon fallback"
  assert_eq "status-service" "${service_role_key}" "service fallback"

  write_stub "${stubbin}/supabase" 'if [ "$1" = "status" ]; then printf ""; exit 0; fi; exit 0'
  assert_failure "extract key fail" extract_values_from_output "${sample_output}"

  PATH="${old_path}"
  pass "setup: extract_values branches"
}

run_test_start_supabase_branches() {
  local tmp stubbin old_path
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"

  write_stub "${stubbin}/supabase" 'if [ "$1" = "start" ]; then exit 1; fi; if [ "$1" = "status" ]; then printf "anon key: a\nservice_role key: s\n"; fi; exit 0'
  PATH="${stubbin}:${old_path}"
  assert_failure "start_supabase fail" start_supabase

  write_stub "${stubbin}/supabase" 'if [ "$1" = "start" ]; then printf "API URL: http://127.0.0.1:54321\nanon key: a\nservice_role key: s\n"; exit 0; fi; exit 0'
  assert_success "start_supabase ok" start_supabase
  assert_eq "a" "${anon_key}" "anon after start"

  PATH="${old_path}"
  pass "setup: start_supabase branches"
}

run_test_project_id_and_volume() {
  local tmp cfg
  tmp="$(new_temp_dir)"
  cfg="${tmp}/config.toml"
  cp "${REPO_ROOT}/supabase/config.toml" "${cfg}"
  CONFIG_FILE="${cfg}"
  project_id=""

  # set_project_id: valid name
  assert_success "set_project_id valid" set_project_id "MyApp 1"
  assert_eq "myapp-1" "${project_id}" "project_id sanitized"
  assert_file_contains "${cfg}" 'project_id = "myapp-1"' "config patched"

  # set_project_id: invalid name (all hyphens after sanitize)
  assert_failure "set_project_id invalid" set_project_id "---"

  # read_project_id_from_config
  local read_val
  read_val="$(read_project_id_from_config)"
  assert_eq "myapp-1" "${read_val}" "read_project_id_from_config"

  # check_existing_volume: stub docker to report volume present
  local stubbin old_path
  stubbin="${tmp}/bin2"
  make_stub_bin "${stubbin}"
  old_path="${PATH}"

  write_stub "${stubbin}/docker" 'printf "supabase_db_myapp-1\n"; exit 0'
  PATH="${stubbin}:${old_path}"
  project_id="myapp-1"
  assert_success "check_existing_volume exists" check_existing_volume

  write_stub "${stubbin}/docker" 'printf "supabase_db_other\n"; exit 0'
  assert_success "check_existing_volume new" check_existing_volume

  # reset_volume: stub supabase + docker
  write_stub "${stubbin}/supabase" 'exit 0'
  assert_success "reset_volume" reset_volume

  PATH="${old_path}"
  pass "setup: project_id and volume"
}

run_test_write_env_and_main() {
  local tmp stubbin old_path cfg
  tmp="$(new_temp_dir)"
  stubbin="${tmp}/bin"
  make_stub_bin "${stubbin}"
  cfg="${tmp}/config.toml"
  cp "${REPO_ROOT}/supabase/config.toml" "${cfg}"
  CONFIG_FILE="${cfg}"
  PORTS_FILE="${tmp}/.ports"
  REPO_ROOT="${tmp}"
  mkdir -p "${tmp}/repo"

  old_path="${PATH}"
  write_stub "${stubbin}/docker" 'printf "supabase_db_localsupabasedb\n"; exit 0'
  write_stub "${stubbin}/lsof" 'if [ "${LSOF_BUSY:-0}" = "1" ]; then exit 0; fi; exit 1'
  write_stub "${stubbin}/supabase" 'if [ "$1" = "--version" ]; then echo "2.0.0"; exit 0; fi; if [ "$1" = "start" ]; then printf "API URL: http://127.0.0.1:54321\nanon key: anon\nservice_role key: service\n"; exit 0; fi; if [ "$1" = "status" ]; then printf "anon key: anon\nservice_role key: service\n"; exit 0; fi; exit 0'
  PATH="${stubbin}:${old_path}"

  api_url="http://127.0.0.1:54321"
  anon_key="anon"
  service_role_key="service"
  configure_target_dir "${tmp}"
  rm -f "${TARGET_ENV_FILE}" "${TARGET_ENV_BACKUP}"
  assert_success "write_env_file ohne backup" write_env_file

  configure_target_dir "${tmp}"
  echo "EXISTING=1" > "${TARGET_ENV_FILE}"
  assert_success "write_env_file backup" write_env_file
  assert_file_contains "${TARGET_ENV_BACKUP}" "EXISTING=1" "backup file exists"

  configure_target_dir "${tmp}"
  is_port_free() { return 0; }
  assert_success "main happy path" main "${tmp}"
  assert_file_contains "${PORTS_FILE}" "API_PORT=" "ports file created"
  assert_file_contains "${TARGET_ENV_FILE}" "NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321" "env file created"

  # main with --app flag
  assert_success "main with --app" main --app testapp "${tmp}"
  assert_file_contains "${cfg}" 'project_id = "testapp"' "project_id set by --app"

  PATH="${old_path}"
  pass "setup: write_env and main"
}

run_test_setup_target_dir
run_test_is_port_free_branches
run_test_apply_ports_to_config
run_test_check_prerequisites_branches
run_test_select_port_block_branches
run_test_extract_values_branches
run_test_start_supabase_branches
run_test_project_id_and_volume
run_test_write_env_and_main

pass "setup tests complete"
