ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "username" TEXT;

CREATE INDEX IF NOT EXISTS "profiles_tenant_id_username_idx"
  ON "profiles"("tenant_id", "username");
