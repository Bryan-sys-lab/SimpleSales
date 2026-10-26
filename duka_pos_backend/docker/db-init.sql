-- The databases besides the app one. The postgres image seeds exactly one
-- database (POSTGRES_DB), so Keycloak's realm storage is created here, by
-- idempotent SQL, before Keycloak ever connects.
--
-- The password matches docker-compose.yml's local default (KC_DB_PASSWORD);
-- a real deployment supplies the same value through .env to BOTH places, and
-- nothing here is a secret on its own.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'keycloak') THEN
    CREATE ROLE keycloak LOGIN PASSWORD 'keycloak_local_dev';
  ELSE
    ALTER ROLE keycloak LOGIN PASSWORD 'keycloak_local_dev';
  END IF;
END
$$;

SELECT 'CREATE DATABASE keycloak OWNER keycloak'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'keycloak')\gexec

ALTER DATABASE keycloak OWNER TO keycloak;
