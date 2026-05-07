#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="/home/runner/work/localSupabaseDB/localSupabaseDB"
TMP_DIR="$(mktemp -d)"
COVERAGE_FILE="${TMP_DIR}/coverage.log"
export COVERAGE_FILE

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

bash "${REPO_ROOT}/tests/test_setup.sh"
bash "${REPO_ROOT}/tests/test_stop.sh"
bash "${REPO_ROOT}/tests/test_status.sh"
bash "${REPO_ROOT}/tests/check_coverage.sh" "${COVERAGE_FILE}"

echo "Alle Tests und Coverage-Checks erfolgreich."
