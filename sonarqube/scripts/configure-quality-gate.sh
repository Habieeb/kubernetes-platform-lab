#!/usr/bin/env bash
set -euo pipefail

SONAR_URL="${SONAR_URL:-http://platform-lab-sonarqube:9000}"
PROJECT_KEY="${SONAR_PROJECT_KEY:-platform-lab-backend}"
GATE_NAME="${SONAR_GATE_NAME:-Platform Lab Quality Gate}"

if [[ -z "${SONAR_TOKEN:-}" ]]; then
    echo "ERROR: SONAR_TOKEN is required."
    exit 1
fi

sonar_api() {
    curl --fail --silent --show-error \
        -u "${SONAR_TOKEN}:" \
        "$@"
}

echo "=== SonarQube Quality Gate Bootstrap ==="
echo "Server:  ${SONAR_URL}"
echo "Project: ${PROJECT_KEY}"
echo "Gate:    ${GATE_NAME}"

#
# Create the gate if it does not already exist.
#
if sonar_api \
    --get \
    "${SONAR_URL}/api/qualitygates/show" \
    --data-urlencode "name=${GATE_NAME}" \
    >/dev/null 2>&1
then
    echo "Quality Gate already exists."
else
    echo "Creating Quality Gate..."

    sonar_api \
        -X POST \
        "${SONAR_URL}/api/qualitygates/create" \
        --data-urlencode "name=${GATE_NAME}" \
        >/dev/null
fi

#
# Read current gate configuration.
#
EXISTING="$(
    sonar_api \
        --get \
        "${SONAR_URL}/api/qualitygates/show" \
        --data-urlencode "name=${GATE_NAME}"
)"

ensure_condition() {
    local metric="$1"
    local operator="$2"
    local error="$3"

    if printf '%s' "${EXISTING}" |
        python3 -c '
import json, sys

metric = sys.argv[1]
operator = sys.argv[2]
error = sys.argv[3]

data = json.load(sys.stdin)

matched = any(
    c.get("metric") == metric
    and c.get("op") == operator
    and str(c.get("error")) == error
    for c in data.get("conditions", [])
)

sys.exit(0 if matched else 1)
' "${metric}" "${operator}" "${error}"
    then
        echo "Condition correct: ${metric} ${operator} ${error}"
    else
        echo "ERROR: Expected condition is missing or different:"
        echo "       ${metric} ${operator} ${error}"
        echo "Refusing to create a duplicate condition."
        exit 1
    fi
}

#
# Desired Quality Gate policy.
#
ensure_condition "new_violations" "GT" "0"
ensure_condition "new_coverage" "LT" "80"
ensure_condition "new_duplicated_lines_density" "GT" "3"
ensure_condition "new_security_hotspots_reviewed" "LT" "100"

#
# Assign the Quality Gate to the backend project.
#
echo "Assigning Quality Gate to ${PROJECT_KEY}..."

sonar_api \
    -X POST \
    "${SONAR_URL}/api/qualitygates/select" \
    --data-urlencode "projectKey=${PROJECT_KEY}" \
    --data-urlencode "gateName=${GATE_NAME}" \
    >/dev/null

echo
echo "Quality Gate configuration complete."
echo "Gate:    ${GATE_NAME}"
echo "Project: ${PROJECT_KEY}"
