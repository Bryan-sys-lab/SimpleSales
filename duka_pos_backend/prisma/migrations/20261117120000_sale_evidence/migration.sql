CREATE TABLE "sale_evidence" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "sale_id" TEXT,
  "device_id" TEXT NOT NULL DEFAULT 'legacy',
  "local_id" INTEGER NOT NULL,
  "object_key" TEXT NOT NULL,
  "public_url" TEXT,
  "mime_type" TEXT NOT NULL,
  "byte_size" INTEGER,
  "created_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "sale_evidence_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "sale_evidence_tenant_id_device_id_local_id_object_key_key"
  ON "sale_evidence"("tenant_id", "device_id", "local_id", "object_key");
CREATE INDEX "sale_evidence_tenant_id_device_id_local_id_idx"
  ON "sale_evidence"("tenant_id", "device_id", "local_id");
ALTER TABLE "sale_evidence" ADD CONSTRAINT "sale_evidence_tenant_id_fkey"
  FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "sale_evidence" ADD CONSTRAINT "sale_evidence_sale_id_fkey"
  FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE SET NULL ON UPDATE CASCADE;
