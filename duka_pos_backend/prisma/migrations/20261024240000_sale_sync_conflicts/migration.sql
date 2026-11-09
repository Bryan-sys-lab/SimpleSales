CREATE TABLE "sale_sync_conflicts" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "device_id" TEXT NOT NULL,
  "local_id" INTEGER NOT NULL,
  "payload" JSONB NOT NULL,
  "reason" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'open',
  "resolution" TEXT,
  "resolved_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "resolved_at" TIMESTAMP(3),
  CONSTRAINT "sale_sync_conflicts_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "sale_sync_conflicts_tenant_id_device_id_local_id_key"
  ON "sale_sync_conflicts"("tenant_id", "device_id", "local_id");
CREATE INDEX "sale_sync_conflicts_tenant_id_status_created_at_idx"
  ON "sale_sync_conflicts"("tenant_id", "status", "created_at");
ALTER TABLE "sale_sync_conflicts"
  ADD CONSTRAINT "sale_sync_conflicts_tenant_id_fkey"
  FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
