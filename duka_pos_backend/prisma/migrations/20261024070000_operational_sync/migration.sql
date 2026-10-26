CREATE TABLE "sync_records" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "local_id" INTEGER NOT NULL,
    "payload" JSONB NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "sync_records_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "sync_records_tenant_id_kind_local_id_key" ON "sync_records"("tenant_id", "kind", "local_id");
CREATE INDEX "sync_records_tenant_id_kind_created_at_idx" ON "sync_records"("tenant_id", "kind", "created_at");
ALTER TABLE "sync_records" ADD CONSTRAINT "sync_records_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
