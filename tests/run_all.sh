#!/usr/bin/env bash
set -euo pipefail

# REPO_ROOT: In CI über $GITHUB_WORKSPACE gesetzt, lokal relativ zur Skript-Position ermittelt.
REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
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
bash "${REPO_ROOT}/tests/test_config.sh"
bash "${REPO_ROOT}/tests/check_coverage.sh" "${COVERAGE_FILE}"

echo "Alle Tests und Coverage-Checks erfolgreich."
