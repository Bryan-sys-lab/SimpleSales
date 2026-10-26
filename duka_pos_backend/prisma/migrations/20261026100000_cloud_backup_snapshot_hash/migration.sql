ALTER TABLE "cloud_backups"
    ADD COLUMN "snapshot_hash" TEXT;

CREATE UNIQUE INDEX "cloud_backups_tenant_id_workspace_key_kind_snapshot_hash_key"
    ON "cloud_backups"("tenant_id", "workspace_key", "kind", "snapshot_hash");
