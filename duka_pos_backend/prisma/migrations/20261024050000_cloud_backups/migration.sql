CREATE TABLE "cloud_backups" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "workspace_key" TEXT NOT NULL,
    "payload" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "cloud_backups_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "cloud_backups_tenant_id_workspace_key_created_at_idx"
    ON "cloud_backups"("tenant_id", "workspace_key", "created_at");

ALTER TABLE "cloud_backups"
    ADD CONSTRAINT "cloud_backups_tenant_id_fkey"
    FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id")
    ON DELETE CASCADE ON UPDATE CASCADE;
