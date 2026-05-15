#!/usr/bin/env bash
set -euo pipefail

# REPO_ROOT: In CI über $GITHUB_WORKSPACE gesetzt, lokal relativ zur Skript-Position ermittelt.
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck disable=SC1091
source "${REPO_ROOT}/tests/lib.sh"

TEMPLATE="${REPO_ROOT}/supabase/config.toml.template"

run_test_template_exists() {
  [ -f "${TEMPLATE}" ] || fail "config.toml.template fehlt"
  pass "config: template vorhanden"
}

run_test_template_required_sections() {
  assert_file_contains "${TEMPLATE}" '[api]'      "template: [api] Sektion"
  assert_file_contains "${TEMPLATE}" '[db]'       "template: [db] Sektion"
  assert_file_contains "${TEMPLATE}" '[studio]'   "template: [studio] Sektion"
  assert_file_contains "${TEMPLATE}" '[inbucket]' "template: [inbucket] Sektion"
  assert_file_contains "${TEMPLATE}" '[analytics]' "template: [analytics] Sektion"
  assert_file_contains "${TEMPLATE}" '[auth]'     "template: [auth] Sektion"
  pass "config: alle Pflicht-Sektionen vorhanden"
}

run_test_template_default_project_id() {
  assert_file_contains "${TEMPLATE}" 'project_id = "localSupabaseDB"' "template: Standard project_id"
  pass "config: Standard project_id korrekt"
}

run_test_template_ports_are_numbers() {
  local port_count
  port_count=$(grep -c '^port = [0-9]' "${TEMPLATE}")
  [ "${port_count}" -ge 4 ] || fail "Erwartet mind. 4 Port-Einträge, gefunden: ${port_count}"
  pass "config: mindestens 4 Port-Einträge"
}

run_test_template_no_gitignored_secrets() {
  # Template darf keine echten Keys/Secrets enthalten
  assert_file_not_contains "${TEMPLATE}" 'eyJ'           "template: keine JWT-Tokens"
  assert_file_not_contains "${TEMPLATE}" 'sb_publishable_' "template: keine echten Anon-Keys"
  assert_file_not_contains "${TEMPLATE}" 'sb_secret_'    "template: keine echten Service-Keys"
  pass "config: keine Secrets im Template"
}

run_test_template_site_url_placeholder() {
  assert_file_contains "${TEMPLATE}" 'site_url = "http://localhost:' "template: site_url Platzhalter"
  pass "config: site_url Platzhalter vorhanden"
}

run_test_env_example_structure() {
  local example="${REPO_ROOT}/.env.local.example"
  if [ -f "${example}" ]; then
    assert_file_contains "${example}" 'NEXT_PUBLIC_SUPABASE_URL'       ".env.example: URL-Key"
    assert_file_contains "${example}" 'NEXT_PUBLIC_SUPABASE_ANON_KEY'  ".env.example: Anon-Key"
    assert_file_not_contains "${example}" 'sb_publishable_' ".env.example: keine echten Anon-Keys"
    pass "config: .env.local.example Struktur"
  else
    pass "config: .env.local.example optional – nicht vorhanden"
  fi
}

run_test_seed_sql_readable() {
  local seed="${REPO_ROOT}/supabase/seed.sql"
  if [ -f "${seed}" ]; then
    [ -r "${seed}" ] || fail "seed.sql ist nicht lesbar"
    pass "config: seed.sql lesbar"
  else
    pass "config: seed.sql optional – nicht vorhanden"
  fi
}

run_test_template_email_confirmations_disabled() {
  # Im lokalen Dev sollen E-Mail-Bestätigungen deaktiviert sein
  assert_file_contains "${TEMPLATE}" 'enable_confirmations = false' "template: E-Mail-Bestätigung deaktiviert"
  pass "config: E-Mail-Bestätigung lokal deaktiviert"
}

run_test_template_exists
run_test_template_required_sections
run_test_template_default_project_id
run_test_template_ports_are_numbers
run_test_template_no_gitignored_secrets
run_test_template_site_url_placeholder
run_test_env_example_structure
run_test_seed_sql_readable
run_test_template_email_confirmations_disabled

pass "config tests complete"
