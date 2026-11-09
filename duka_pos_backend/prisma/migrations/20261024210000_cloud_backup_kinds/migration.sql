ALTER TABLE "cloud_backups"
  ADD COLUMN IF NOT EXISTS "kind" TEXT NOT NULL DEFAULT 'device_bound';

DROP INDEX IF EXISTS "cloud_backups_tenant_id_workspace_key_created_at_idx";
CREATE INDEX IF NOT EXISTS "cloud_backups_tenant_id_workspace_key_kind_created_at_idx"
  ON "cloud_backups"("tenant_id", "workspace_key", "kind", "created_at");
