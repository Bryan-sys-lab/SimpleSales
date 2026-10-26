ALTER TABLE "sync_records"
  ADD COLUMN IF NOT EXISTS "device_id" TEXT NOT NULL DEFAULT 'legacy';

DROP INDEX IF EXISTS "sync_records_tenant_id_kind_local_id_key";

CREATE UNIQUE INDEX IF NOT EXISTS "sync_records_tenant_id_kind_device_id_local_id_key"
  ON "sync_records"("tenant_id", "kind", "device_id", "local_id");
