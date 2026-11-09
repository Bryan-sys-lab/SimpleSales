-- eTIMS: KRA electronic tax invoicing.
--
-- Additive and re-runnable, like every migration in this chain: a shop that
-- never turns eTIMS on pays nothing but three empty tables, and applying this
-- to a database that already has them is a no-op.
--
-- Two decisions worth stating, because both would be expensive to reverse:
--
--  1. Receipt amounts are DECIMAL, not an integer minor-unit type. The mobile
--     app sends integer cents because it can, but the backend also accepts
--     amounts from the PayHero webhook and from operator-entered Z-reports,
--     where the source figure is major units. Storing Decimal means there is
--     exactly one representation of money in this database rather than two,
--     and therefore no conversion that could be forgotten. The conversion from
--     the till's cents happens once, in routes/etims.ts.
--
--  2. `etims_receipts` carries its own unique (tenant_id, receipt_number)
--     constraint rather than relying on KRA to reject a duplicate. KRA's own
--     duplicate rejection is slow, costs a round-trip and only reports the
--     problem after it has already refused an invoice; catching it here turns
--     a retried upload into a no-op instead of an error the till will keep
--     retrying forever.

CREATE TABLE IF NOT EXISTS "etims_devices" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "tin" TEXT NOT NULL,
  "device_id" TEXT NOT NULL,
  "device_name" TEXT NOT NULL DEFAULT '',
  "status" TEXT NOT NULL DEFAULT 'unregistered',
  "encryption_key" TEXT,
  "access_key" TEXT,
  "device_serial" TEXT,
  "initialised_at" TIMESTAMP(3),
  "last_error" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "etims_devices_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "etims_receipts" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "device_id" TEXT,
  "receipt_number" TEXT NOT NULL,
  "kra_receipt_number" TEXT,
  "payload" JSONB NOT NULL,
  "total" DECIMAL(14,2) NOT NULL,
  "vat_total" DECIMAL(14,2) NOT NULL,
  "vat_rate_percent" INTEGER NOT NULL DEFAULT 16,
  "item_count" INTEGER NOT NULL DEFAULT 0,
  "payment_method" TEXT NOT NULL DEFAULT 'cash',
  "payment_reference" TEXT,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "rejection_reason" TEXT,
  "issued_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "etims_receipts_pkey" PRIMARY KEY ("id")
);

CREATE TABLE IF NOT EXISTS "etims_z_reports" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "device_id" TEXT,
  "z_number" INTEGER NOT NULL,
  "business_date" TIMESTAMP(3) NOT NULL,
  "invoice_count" INTEGER NOT NULL DEFAULT 0,
  "total" DECIMAL(14,2) NOT NULL,
  "vat_total" DECIMAL(14,2) NOT NULL,
  "pending_count" INTEGER NOT NULL DEFAULT 0,
  "rejected_count" INTEGER NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "failure_reason" TEXT,
  "raw_response" JSONB,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "etims_z_reports_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "etims_devices_tenant_id_key" ON "etims_devices"("tenant_id");
CREATE UNIQUE INDEX IF NOT EXISTS "etims_receipts_tenant_id_receipt_number_key" ON "etims_receipts"("tenant_id", "receipt_number");
CREATE INDEX IF NOT EXISTS "etims_receipts_tenant_id_status_idx" ON "etims_receipts"("tenant_id", "status");
-- Globally unique because the public verification page looks a receipt up with
-- no tenant filter: the person following the QR is a customer who has no
-- account. A KRA receipt number is a UUID and so satisfies that. `receipt_number`
-- does not — it is unique per shop only, and "T1-000001" is a number several
-- shops will independently reach. Postgres permits many NULLs under a unique
-- index, so the pre-issuance rows are unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS "etims_receipts_kra_receipt_number_key" ON "etims_receipts"("kra_receipt_number");
CREATE UNIQUE INDEX IF NOT EXISTS "etims_z_reports_tenant_id_business_date_key" ON "etims_z_reports"("tenant_id", "business_date");
CREATE INDEX IF NOT EXISTS "etims_z_reports_tenant_id_z_number_idx" ON "etims_z_reports"("tenant_id", "z_number");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'etims_devices_tenant_id_fkey') THEN
    ALTER TABLE "etims_devices" ADD CONSTRAINT "etims_devices_tenant_id_fkey"
      FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'etims_receipts_tenant_id_fkey') THEN
    ALTER TABLE "etims_receipts" ADD CONSTRAINT "etims_receipts_tenant_id_fkey"
      FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'etims_receipts_device_id_fkey') THEN
    ALTER TABLE "etims_receipts" ADD CONSTRAINT "etims_receipts_device_id_fkey"
      FOREIGN KEY ("device_id") REFERENCES "etims_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'etims_z_reports_tenant_id_fkey') THEN
    ALTER TABLE "etims_z_reports" ADD CONSTRAINT "etims_z_reports_tenant_id_fkey"
      FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'etims_z_reports_device_id_fkey') THEN
    ALTER TABLE "etims_z_reports" ADD CONSTRAINT "etims_z_reports_device_id_fkey"
      FOREIGN KEY ("device_id") REFERENCES "etims_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;
  END IF;
END
$$;
