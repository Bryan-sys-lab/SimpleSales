#!/bin/bash
set -e

# Start Keycloak in background
export KC_DB="${KC_DB:-h2}"
export KC_HEALTH_ENABLED=true
export KC_METRICS_ENABLED=true
export KC_HTTP_ENABLED=true
export KC_HTTP_PORT=8080
export KC_PROXY_HEADERS=xforwarded
export KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
export KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin_local_dev}"

# Only set DB URL for non-H2 databases (H2 uses embedded default)
if [ "$KC_DB" != "h2" ]; then
  export KC_DB_URL="${KC_DB_URL}"
  export KC_DB_USERNAME="${KC_DB_USERNAME:-keycloak}"
  export KC_DB_PASSWORD="${KC_DB_PASSWORD:-keycloak}"
fi

/opt/keycloak/bin/kc.sh start-dev &
KC_PID=$!

# Wait for Keycloak to be ready
for i in $(seq 1 120); do
  if curl -sf http://localhost:8080/realms/master > /dev/null 2>&1; then
    echo "Keycloak is ready"
    break
  fi
  sleep 2
done

# Run keycloak-init to set up realm, client, and test user
sleep 5
node keycloak-init.mjs || echo "Keycloak init failed, continuing..."

# Start backend
exec node dist/index.js
