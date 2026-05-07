#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bash -n "${REPO_ROOT}/scripts/setup.sh"
bash -n "${REPO_ROOT}/scripts/stop.sh"
bash -n "${REPO_ROOT}/scripts/status.sh"
bash -n "${REPO_ROOT}/tests/test_setup.sh"
bash -n "${REPO_ROOT}/tests/test_stop.sh"
bash -n "${REPO_ROOT}/tests/test_status.sh"
bash -n "${REPO_ROOT}/tests/run_all.sh"
bash "${REPO_ROOT}/tests/run_all.sh"

echo "Validierung vollständig erfolgreich."
