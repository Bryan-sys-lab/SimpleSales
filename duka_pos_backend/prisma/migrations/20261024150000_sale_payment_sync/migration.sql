-- Preserve each offline tender on the server so split payments survive
-- multishop sync and payment-mix analytics.
CREATE TABLE IF NOT EXISTS "sale_payments" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "sale_id" TEXT NOT NULL,
  "local_uuid" TEXT NOT NULL,
  "method" TEXT NOT NULL,
  "amount" DECIMAL(12,2) NOT NULL,
  "tendered" DECIMAL(12,2),
  "change" DECIMAL(12,2),
  "reference" TEXT,
  "status" TEXT NOT NULL DEFAULT 'confirmed',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "sale_payments_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "sale_payments_tenant_id_local_uuid_key"
  ON "sale_payments"("tenant_id", "local_uuid");
CREATE INDEX IF NOT EXISTS "sale_payments_tenant_id_sale_id_idx"
  ON "sale_payments"("tenant_id", "sale_id");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sale_payments_tenant_id_fkey') THEN
    ALTER TABLE "sale_payments"
      ADD CONSTRAINT "sale_payments_tenant_id_fkey"
      FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'sale_payments_sale_id_fkey') THEN
    ALTER TABLE "sale_payments"
      ADD CONSTRAINT "sale_payments_sale_id_fkey"
      FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;
