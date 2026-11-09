-- The eTIMS device holds KRA's access and encryption keys; the receipt rows
-- carry the till's invoice figures; and the Z report is stored per business
-- date so a re-run replaces the same day instead of minting a second Z number.
-- Additive only: no existing column is dropped or rewritten.

-- The first eTIMS migration in this repository used the database's mapped
-- snake_case names. This older follow-up was generated from an intermediate
-- Prisma model and refers to its unmapped camelCase names. Keep the chain
-- usable for fresh databases (and for legacy databases that already have the
-- snake_case shape) by materialising that intermediate shape here. The next
-- alignment migration deliberately removes these compatibility columns after
-- it has normalised the schema.

ALTER TABLE "etims_devices"
  ADD COLUMN IF NOT EXISTS "tenantId" TEXT,
  ADD COLUMN IF NOT EXISTS "deviceSerial" TEXT,
  ADD COLUMN IF NOT EXISTS "accessKey" TEXT,
  ADD COLUMN IF NOT EXISTS "encryptionKey" TEXT,
  ADD COLUMN IF NOT EXISTS "initialisedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "lastError" TEXT;

UPDATE "etims_devices"
   SET "tenantId" = COALESCE("tenantId", "tenant_id"),
       "deviceSerial" = COALESCE("deviceSerial", "device_serial"),
       "accessKey" = COALESCE("accessKey", "access_key"),
       "encryptionKey" = COALESCE("encryptionKey", "encryption_key"),
       "initialisedAt" = COALESCE("initialisedAt", "initialised_at"),
       "lastError" = COALESCE("lastError", "last_error");

ALTER TABLE "etims_receipts"
  ADD COLUMN IF NOT EXISTS "tenantId" TEXT,
  ADD COLUMN IF NOT EXISTS "deviceId" TEXT,
  ADD COLUMN IF NOT EXISTS "receiptNumber" TEXT,
  ADD COLUMN IF NOT EXISTS "kraReceiptNumber" TEXT,
  ADD COLUMN IF NOT EXISTS "total" TEXT,
  ADD COLUMN IF NOT EXISTS "vatTotal" TEXT,
  ADD COLUMN IF NOT EXISTS "vatRatePercent" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "itemCount" INTEGER,
  ADD COLUMN IF NOT EXISTS "paymentMethod" TEXT,
  ADD COLUMN IF NOT EXISTS "paymentReference" TEXT,
  ADD COLUMN IF NOT EXISTS "rejectionReason" TEXT,
  ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3);

UPDATE "etims_receipts"
   SET "tenantId" = COALESCE("tenantId", "tenant_id"),
       "deviceId" = COALESCE("deviceId", "device_id"),
       "receiptNumber" = COALESCE("receiptNumber", "receipt_number"),
       "kraReceiptNumber" = COALESCE("kraReceiptNumber", "kra_receipt_number"),
       "vatTotal" = COALESCE("vatTotal", "vat_total"::TEXT),
       "vatRatePercent" = COALESCE("vatRatePercent", vat_rate_percent),
       "itemCount" = COALESCE("itemCount", item_count),
       "paymentMethod" = COALESCE("paymentMethod", payment_method),
       "paymentReference" = COALESCE("paymentReference", payment_reference),
       "rejectionReason" = COALESCE("rejectionReason", rejection_reason),
       "createdAt" = COALESCE("createdAt", created_at);

ALTER TABLE "etims_z_reports"
  ADD COLUMN IF NOT EXISTS "tenantId" TEXT,
  ADD COLUMN IF NOT EXISTS "deviceId" TEXT,
  ADD COLUMN IF NOT EXISTS "zNumber" INTEGER,
  ADD COLUMN IF NOT EXISTS "businessDate" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "invoiceCount" INTEGER,
  ADD COLUMN IF NOT EXISTS "total" TEXT,
  ADD COLUMN IF NOT EXISTS "vatTotal" TEXT,
  ADD COLUMN IF NOT EXISTS "pendingCount" INTEGER,
  ADD COLUMN IF NOT EXISTS "rejectedCount" INTEGER,
  ADD COLUMN IF NOT EXISTS "failureReason" TEXT,
  ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3);

UPDATE "etims_z_reports"
   SET "tenantId" = COALESCE("tenantId", "tenant_id"),
       "deviceId" = COALESCE("deviceId", "device_id"),
       "zNumber" = COALESCE("zNumber", z_number),
       "businessDate" = COALESCE("businessDate", business_date),
       "invoiceCount" = COALESCE("invoiceCount", invoice_count),
       "vatTotal" = COALESCE("vatTotal", "vat_total"::TEXT),
       "pendingCount" = COALESCE("pendingCount", pending_count),
       "rejectedCount" = COALESCE("rejectedCount", rejected_count),
       "failureReason" = COALESCE("failureReason", failure_reason),
       "createdAt" = COALESCE("createdAt", created_at);

ALTER TABLE "etims_devices"
  ADD COLUMN IF NOT EXISTS "deviceSerial" TEXT,
  ADD COLUMN IF NOT EXISTS "status" TEXT NOT NULL DEFAULT 'unregistered',
  ADD COLUMN IF NOT EXISTS "accessKey" TEXT,
  ADD COLUMN IF NOT EXISTS "encryptionKey" TEXT,
  ADD COLUMN IF NOT EXISTS "initialisedAt" TIMESTAMP(3),
  ADD COLUMN IF NOT EXISTS "lastError" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "etims_devices_tenantId_key" ON "etims_devices"("tenantId");

ALTER TABLE "etims_receipts"
  ADD COLUMN IF NOT EXISTS "receiptNumber" TEXT,
  ADD COLUMN IF NOT EXISTS "total" TEXT,
  ADD COLUMN IF NOT EXISTS "vatTotal" TEXT,
  ADD COLUMN IF NOT EXISTS "vatRatePercent" DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS "itemCount" INTEGER,
  ADD COLUMN IF NOT EXISTS "paymentMethod" TEXT,
  ADD COLUMN IF NOT EXISTS "paymentReference" TEXT,
  ADD COLUMN IF NOT EXISTS "rejectionReason" TEXT,
  ADD COLUMN IF NOT EXISTS "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Backfill the till receipt number from the KRA-issued one for rows issued
-- before the column existed, then make the pair unique.
UPDATE "etims_receipts" SET "receiptNumber" = "kraReceiptNumber"
WHERE "receiptNumber" IS NULL AND "kraReceiptNumber" IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS "etims_receipts_tenantId_receiptNumber_key"
  ON "etims_receipts"("tenantId", "receiptNumber");
CREATE INDEX IF NOT EXISTS "etims_receipts_status_idx" ON "etims_receipts"("status");
CREATE INDEX IF NOT EXISTS "etims_receipts_createdAt_idx" ON "etims_receipts"("createdAt");

-- A receipt is created before KRA answers, so the KRA number arrives later:
ALTER TABLE "etims_receipts"
  ALTER COLUMN "kraReceiptNumber" DROP NOT NULL;

CREATE TABLE IF NOT EXISTS "etims_z_reports" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "deviceId" TEXT,
  "zNumber" INTEGER NOT NULL,
  "businessDate" TIMESTAMP(3) NOT NULL,
  "invoiceCount" INTEGER NOT NULL DEFAULT 0,
  "total" TEXT NOT NULL DEFAULT '0.00',
  "vatTotal" TEXT NOT NULL DEFAULT '0.00',
  "pendingCount" INTEGER NOT NULL DEFAULT 0,
  "rejectedCount" INTEGER NOT NULL DEFAULT 0,
  "status" TEXT NOT NULL DEFAULT 'issued',
  "failureReason" TEXT,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

  CONSTRAINT "etims_z_reports_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "etims_z_reports_tenantId_businessDate_key"
  ON "etims_z_reports"("tenantId", "businessDate");
CREATE INDEX IF NOT EXISTS "etims_z_reports_tenantId_idx" ON "etims_z_reports"("tenantId");
CREATE INDEX IF NOT EXISTS "etims_z_reports_businessDate_idx" ON "etims_z_reports"("businessDate");

ALTER TABLE "etims_receipts"
  ADD CONSTRAINT "etims_receipts_deviceId_fkey"
  FOREIGN KEY ("deviceId") REFERENCES "etims_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;

ALTER TABLE "etims_z_reports"
  ADD CONSTRAINT "etims_z_reports_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
ALTER TABLE "etims_z_reports"
  ADD CONSTRAINT "etims_z_reports_deviceId_fkey"
  FOREIGN KEY ("deviceId") REFERENCES "etims_devices"("id") ON DELETE SET NULL ON UPDATE CASCADE;
