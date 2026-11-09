-- Staff usernames are scoped to a tenant. PostgreSQL's unique-index NULL
-- semantics keep legacy rows without a username valid.
DROP INDEX IF EXISTS "profiles_tenant_id_username_idx";
CREATE UNIQUE INDEX IF NOT EXISTS "profiles_tenant_id_username_key"
  ON "profiles"("tenant_id", "username");
