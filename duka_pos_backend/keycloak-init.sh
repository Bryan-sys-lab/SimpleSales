#!/bin/bash
set -e

KEYCLOAK_URL="${KEYCLOAK_URL:-http://keycloak:8080}"
KEYCLOAK_ADMIN="${KEYCLOAK_ADMIN:-admin}"
KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD:-admin}"
REALM_NAME="${REALM_NAME:-duka}"
CLIENT_ID="${CLIENT_ID:-duka-app}"
TEST_USER="${TEST_USER:-test-user}"
TEST_USER_PASSWORD="${TEST_USER_PASSWORD:-test-password}"
TEST_USER_EMAIL="${TEST_USER_EMAIL:-test-user@example.com}"

# Waiting for Keycloak, by asking for the thing this script needs.
#
# It used to probe /health/ready, which is where the health endpoint LIVES in
# Keycloak 24 — on the MANAGEMENT port, 9000 — while the script talks to the
# main port, 8080. So the probe never succeeded, the loop ran its full five
# minutes, and the script went on to fail for a reason that had nothing to do
# with the cause.
#
# So the probe is the TOKEN ENDPOINT on the port this script uses: if it can
# get a token, Keycloak is up and the admin password works. That tests
# exactly what the script is about to do, instead of a health endpoint on
# another port.
echo "Waiting for Keycloak to be ready at ${KEYCLOAK_URL}..."
ADMIN_TOKEN=""
for i in $(seq 1 60); do
  ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
    -d "grant_type=password" \
    -d "client_id=admin-cli" \
    -d "username=${KEYCLOAK_ADMIN}" \
    -d "password=${KEYCLOAK_ADMIN_PASSWORD}" | jq -r '.access_token // empty' 2>/dev/null || true)
  if [ -n "$ADMIN_TOKEN" ]; then
    echo "Keycloak is ready!"
    break
  fi
  echo "Waiting for Keycloak... (${i}/60)"
  sleep 5
done

if [ -z "$ADMIN_TOKEN" ]; then
  echo "Failed to get admin token: Keycloak did not become ready."
  exit 1
fi

echo "Creating realm ${REALM_NAME}..."
curl -s -X POST "${KEYCLOAK_URL}/admin/realms" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"enabled\": true, \"realm\": \"${REALM_NAME}\", \"displayName\": \"Duka POS\"}" > /dev/null || true

echo "Creating client ${CLIENT_ID}..."
CLIENT_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/clients" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"clientId\": \"${CLIENT_ID}\",
    \"enabled\": true,
    \"publicClient\": true,
    \"protocol\": \"openid-connect\",
    \"standardFlowEnabled\": true,
    \"implicitFlowEnabled\": false,
    \"directAccessGrantsEnabled\": true,
    \"serviceAccountsEnabled\": false,
    \"redirectUris\": [\"http://localhost:*\"],
    \"webOrigins\": [\"*\"]
  }") || true

echo "Client response: ${CLIENT_RESPONSE}"

echo "Creating test user ${TEST_USER}..."
USER_RESPONSE=$(curl -s -X POST "${KEYCLOAK_URL}/admin/realms/${REALM_NAME}/users" \
  -H "Authorization: Bearer ${ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${TEST_USER}\",
    \"email\": \"${TEST_USER_EMAIL}\",
    \"enabled\": true,
    \"emailVerified\": true,
    \"firstName\": \"Test\",
    \"lastName\": \"User\",
    \"credentials\": [{
      \"type\": \"password\",
      \"value\": \"${TEST_USER_PASSWORD}\",
      \"temporary\": false
    }]
  }") || true

echo "User response: ${USER_RESPONSE}"

echo "Keycloak initialization complete!"
echo "Realm: ${REALM_NAME}"
echo "Client: ${CLIENT_ID}"
echo "User: ${TEST_USER}"
