#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${GITHUB_WORKSPACE:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
MARKERS_FILE="${REPO_ROOT}/tests/coverage_markers.txt"
COVERAGE_FILE="${1:-}"

if [ -z "${COVERAGE_FILE}" ] || [ ! -f "${COVERAGE_FILE}" ]; then
  echo "Coverage-Datei fehlt." >&2
  exit 1
fi

total=$(tr -d '\r' < "${MARKERS_FILE}" | wc -l | tr -d ' ')
covered=$(comm -12 <(tr -d '\r' < "${MARKERS_FILE}" | sort -u) <(sort -u "${COVERAGE_FILE}") | wc -l | tr -d ' ')
missing=$(comm -23 <(tr -d '\r' < "${MARKERS_FILE}" | sort -u) <(sort -u "${COVERAGE_FILE}") || true)

percent=$(awk -v c="${covered}" -v t="${total}" 'BEGIN { if (t==0) print "0.00"; else printf "%.2f", (c/t)*100 }')

echo "Marker-Coverage: ${covered}/${total} (${percent}%)"

if [ "${covered}" -ne "${total}" ]; then
  echo "Fehlende Marker:" >&2
  echo "${missing}" >&2
  exit 1
fi

echo "100% Marker-Coverage erreicht."
