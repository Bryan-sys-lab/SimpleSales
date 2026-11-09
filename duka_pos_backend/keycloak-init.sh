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

echo "Waiting for Keycloak to be ready at ${KEYCLOAK_URL}..."
for i in $(seq 1 60); do
  if curl -sf "${KEYCLOAK_URL}/health/ready" > /dev/null 2>&1; then
    echo "Keycloak is ready!"
    break
  fi
  echo "Waiting for Keycloak... (${i}/60)"
  sleep 5
done

# Get admin access token
echo "Getting admin access token..."
ADMIN_TOKEN=$(curl -s -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
  -d "grant_type=password" \
  -d "client_id=admin-cli" \
  -d "username=${KEYCLOAK_ADMIN}" \
  -d "password=${KEYCLOAK_ADMIN_PASSWORD}" | jq -r '.access_token')

if [ -z "$ADMIN_TOKEN" ] || [ "$ADMIN_TOKEN" = "null" ]; then
  echo "Failed to get admin token!"
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
