-- Local integer ids are only unique inside one till database. Namespace them
-- by a persistent device id before accepting multiple tills for one tenant.
ALTER TABLE "sales"
  ADD COLUMN IF NOT EXISTS "device_id" TEXT NOT NULL DEFAULT 'legacy';

DROP INDEX IF EXISTS "sales_tenant_id_local_id_key";

CREATE UNIQUE INDEX IF NOT EXISTS "sales_tenant_id_device_id_local_id_key"
  ON "sales"("tenant_id", "device_id", "local_id")
  WHERE "local_id" IS NOT NULL;
