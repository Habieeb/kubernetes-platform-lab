#!/usr/bin/env bash
set -euo pipefail

CONTAINER="platform-lab-sonarqube"
NETWORK="bridge"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
  echo "ERROR: Container $CONTAINER does not exist."
  exit 1
fi

if docker inspect "$CONTAINER" \
  --format '{{range $name, $_ := .NetworkSettings.Networks}}{{println $name}}{{end}}' \
  | grep -qx "$NETWORK"; then
  echo "$CONTAINER is already attached to $NETWORK."
else
  echo "Attaching $CONTAINER to $NETWORK..."
  docker network connect "$NETWORK" "$CONTAINER"
fi

echo "Testing SonarQube -> Jenkins connectivity..."

curl_output="$(
  docker exec "$CONTAINER" \
    curl -sS -o /dev/null \
    -w '%{http_code}' \
    --connect-timeout 5 \
    http://172.17.0.1:8080/login
)"

if [ "$curl_output" != "200" ]; then
  echo "ERROR: Jenkins returned HTTP $curl_output"
  exit 1
fi

echo "SonarQube -> Jenkins: HTTP 200"
