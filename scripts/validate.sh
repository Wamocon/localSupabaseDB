#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# In CI existiert supabase/config.toml nicht (gitignored).
# Tests kopieren config.toml direkt – daher hier aus Template erzeugen.
if [[ ! -f "${REPO_ROOT}/supabase/config.toml" ]]; then
  cp "${REPO_ROOT}/supabase/config.toml.template" "${REPO_ROOT}/supabase/config.toml"
fi

bash -n "${REPO_ROOT}/scripts/setup.sh"
bash -n "${REPO_ROOT}/scripts/stop.sh"
bash -n "${REPO_ROOT}/scripts/status.sh"
bash -n "${REPO_ROOT}/tests/test_setup.sh"
bash -n "${REPO_ROOT}/tests/test_stop.sh"
bash -n "${REPO_ROOT}/tests/test_status.sh"
bash -n "${REPO_ROOT}/tests/test_config.sh"
bash -n "${REPO_ROOT}/tests/run_all.sh"
bash "${REPO_ROOT}/tests/run_all.sh"

echo "Validierung vollständig erfolgreich."
