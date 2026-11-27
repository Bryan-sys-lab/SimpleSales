ALTER TABLE "tenants"
  ADD COLUMN "payhero_channel_type" TEXT;

ALTER TABLE "tenants"
  ADD COLUMN "payhero_channel_short_code" TEXT;

ALTER TABLE "tenants"
  ADD COLUMN "payhero_channel_account_number" TEXT;

ALTER TABLE "payments"
  ADD COLUMN "operation_id" TEXT;

CREATE UNIQUE INDEX "payments_operation_id_key"
  ON "payments"("operation_id")
  WHERE "operation_id" IS NOT NULL;