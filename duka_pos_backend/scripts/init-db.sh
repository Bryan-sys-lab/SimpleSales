#!/bin/sh
# The database's first-run setup.
#
# The Postgres image runs everything in this directory ONCE, on an empty data
# directory, as the POSTGRES_USER against POSTGRES_DB. So this is the only
# place the identity provider's own role and database can be made.
#
# They have to be made HERE, and not by the Keycloak container, because
# Keycloak connects to an EXISTING database with a role that can log in — it
# does not create either. A stack that skips this fails with "password
# authentication failed for user keycloak", which reads like a wrong password
# and is actually a missing role.
set -e

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
CREATE ROLE keycloak WITH LOGIN PASSWORD '${KEYCLOAK_DB_PASSWORD}';
CREATE DATABASE keycloak OWNER keycloak;
EOSQL

echo "The identity provider's role and database are ready."
