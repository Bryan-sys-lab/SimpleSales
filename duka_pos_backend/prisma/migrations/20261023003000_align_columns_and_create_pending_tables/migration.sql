-- DropForeignKey
ALTER TABLE "deletion_ledger" DROP CONSTRAINT "deletion_ledger_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "etims_devices" DROP CONSTRAINT "etims_devices_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "etims_receipts" DROP CONSTRAINT "etims_receipts_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "etims_z_reports" DROP CONSTRAINT "etims_z_reports_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "mpesa_incoming" DROP CONSTRAINT "mpesa_incoming_tenantId_fkey";

-- DropForeignKey
ALTER TABLE "payments" DROP CONSTRAINT "payments_sale_id_fkey";

-- DropForeignKey
ALTER TABLE "payments" DROP CONSTRAINT "payments_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "products" DROP CONSTRAINT "products_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "profiles" DROP CONSTRAINT "profiles_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "receipt_links" DROP CONSTRAINT "receipt_links_tenantId_fkey";

-- DropForeignKey
ALTER TABLE "sale_items" DROP CONSTRAINT "sale_items_sale_id_fkey";

-- DropForeignKey
ALTER TABLE "sale_items" DROP CONSTRAINT "sale_items_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "sales" DROP CONSTRAINT "sales_tenant_id_fkey";

-- DropForeignKey
ALTER TABLE "stock_adjustments" DROP CONSTRAINT "stock_adjustments_staff_id_fkey";

-- DropForeignKey
ALTER TABLE "stock_adjustments" DROP CONSTRAINT "stock_adjustments_tenant_id_fkey";

-- DropIndex
DROP INDEX "etims_receipts_tenant_id_status_idx";

-- DropIndex
DROP INDEX "etims_z_reports_tenant_id_z_number_idx";

-- DropIndex
DROP INDEX "mpesa_incoming_remoteId_key";

-- DropIndex
DROP INDEX "mpesa_incoming_tenantId_receivedAt_idx";

-- DropIndex
DROP INDEX "mpesa_incoming_transId_key";

-- DropIndex
DROP INDEX "payments_sale_id_key";

-- DropIndex
DROP INDEX "profiles_tenant_id_local_id_key";

-- DropIndex
DROP INDEX "receipt_links_expiresAt_idx";

-- DropIndex
DROP INDEX "receipt_links_tenantId_idx";

-- DropIndex
DROP INDEX "sales_tenant_id_created_at_idx";

-- AlterTable
ALTER TABLE "etims_devices" DROP COLUMN "accessKey",
DROP COLUMN "created_at",
DROP COLUMN "deviceSerial",
DROP COLUMN "encryptionKey",
DROP COLUMN "initialisedAt",
DROP COLUMN "lastError",
DROP COLUMN "updated_at",
ADD COLUMN     "registered_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ALTER COLUMN "device_name" DROP NOT NULL,
ALTER COLUMN "device_name" DROP DEFAULT;

-- AlterTable
ALTER TABLE "etims_receipts" DROP COLUMN "originalReceiptNumber",
DROP COLUMN "returnNumber",
DROP COLUMN "updated_at",
ADD COLUMN     "original_receipt_number" TEXT,
ADD COLUMN     "qr_payload" TEXT,
ADD COLUMN     "return_number" TEXT,
ADD COLUMN     "verification_url" TEXT,
ALTER COLUMN "total" DROP NOT NULL,
ALTER COLUMN "total" SET DATA TYPE TEXT,
ALTER COLUMN "vat_total" DROP NOT NULL,
ALTER COLUMN "vat_total" SET DATA TYPE TEXT,
ALTER COLUMN "vat_rate_percent" DROP NOT NULL,
ALTER COLUMN "vat_rate_percent" DROP DEFAULT,
ALTER COLUMN "vat_rate_percent" SET DATA TYPE DOUBLE PRECISION,
ALTER COLUMN "item_count" DROP NOT NULL,
ALTER COLUMN "item_count" DROP DEFAULT,
ALTER COLUMN "payment_method" DROP NOT NULL,
ALTER COLUMN "payment_method" DROP DEFAULT;

-- AlterTable
ALTER TABLE "etims_z_reports" DROP COLUMN "raw_response",
DROP COLUMN "updated_at",
ALTER COLUMN "total" SET DEFAULT '0.00',
ALTER COLUMN "total" SET DATA TYPE TEXT,
ALTER COLUMN "vat_total" SET DEFAULT '0.00',
ALTER COLUMN "vat_total" SET DATA TYPE TEXT,
ALTER COLUMN "status" SET DEFAULT 'issued';

-- AlterTable
ALTER TABLE "mpesa_incoming" DROP COLUMN "billRef",
DROP COLUMN "claimedAt",
DROP COLUMN "claimedByDevice",
DROP COLUMN "claimedSaleUuid",
DROP COLUMN "createdAt",
DROP COLUMN "ignoreReason",
DROP COLUMN "ignoredAt",
DROP COLUMN "payerLabel",
DROP COLUMN "receivedAt",
DROP COLUMN "remoteId",
DROP COLUMN "tenantId",
DROP COLUMN "transId",
ADD COLUMN     "bill_ref" TEXT,
ADD COLUMN     "claimed_at" TIMESTAMP(3),
ADD COLUMN     "claimed_by_device" TEXT,
ADD COLUMN     "claimed_sale_uuid" TEXT,
ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "ignore_reason" TEXT,
ADD COLUMN     "ignored_at" TIMESTAMP(3),
ADD COLUMN     "payer_label" TEXT NOT NULL,
ADD COLUMN     "received_at" TIMESTAMP(3) NOT NULL,
ADD COLUMN     "remote_id" TEXT NOT NULL,
ADD COLUMN     "tenant_id" TEXT NOT NULL,
ADD COLUMN     "trans_id" TEXT NOT NULL;

-- AlterTable
ALTER TABLE "payments" DROP COLUMN "updated_at",
ALTER COLUMN "amount" SET DATA TYPE DECIMAL(65,30);

-- AlterTable
ALTER TABLE "products" ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "remote_id" TEXT,
ALTER COLUMN "cost_price" SET DEFAULT 0,
ALTER COLUMN "cost_price" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "sell_price" SET DEFAULT 0,
ALTER COLUMN "sell_price" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "stock_qty" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "reorder_level" SET DEFAULT 0,
ALTER COLUMN "half_price" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "quarter_price" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "updated_at" DROP DEFAULT;

-- `photo_url` was added by 20261022150000_profile_photo. Do not add it again
-- here: a fresh database applies both migrations and PostgreSQL rejects the
-- duplicate column.
-- AlterTable
ALTER TABLE "profiles" DROP COLUMN "role",
ADD COLUMN     "role" TEXT NOT NULL DEFAULT 'cashier';

-- AlterTable
ALTER TABLE "receipt_links" DROP COLUMN "createdAt",
DROP COLUMN "expiresAt",
DROP COLUMN "revokedAt",
DROP COLUMN "tenantId",
ADD COLUMN     "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
ADD COLUMN     "expires_at" TIMESTAMP(3) NOT NULL,
ADD COLUMN     "revoked_at" TIMESTAMP(3),
ADD COLUMN     "tenant_id" TEXT NOT NULL;

-- AlterTable
ALTER TABLE "sale_items" ALTER COLUMN "qty" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "unit_price" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "unit_cost" SET DATA TYPE DECIMAL(65,30);

-- AlterTable
ALTER TABLE "sales" ALTER COLUMN "total" SET DEFAULT 0,
ALTER COLUMN "total" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "profit" SET DEFAULT 0,
ALTER COLUMN "profit" SET DATA TYPE DECIMAL(65,30);

-- AlterTable
ALTER TABLE "stock_adjustments" DROP COLUMN "product_name",
ALTER COLUMN "delta" SET DATA TYPE DECIMAL(65,30),
ALTER COLUMN "staff_id" DROP NOT NULL;

-- AlterTable
ALTER TABLE "tenants" ADD COLUMN     "tin" TEXT,
ADD COLUMN     "updated_at" TIMESTAMP(3) NOT NULL;

-- DropTable
DROP TABLE "deletion_ledger";

-- DropEnum
DROP TYPE "UserRole";

-- CreateTable
CREATE TABLE "deletion_ledgers" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "subject_type" TEXT NOT NULL,
    "subject_id" TEXT NOT NULL,
    "reason" TEXT,
    "completed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "deletion_ledgers_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "verification_challenges" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT,
    "email" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "used" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "verification_challenges_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "app_sessions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "access_token" TEXT NOT NULL,
    "refresh_token" TEXT NOT NULL,
    "expires_at" TIMESTAMP(3) NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "app_sessions_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "deletion_ledgers_tenant_id_idx" ON "deletion_ledgers"("tenant_id");

-- CreateIndex
CREATE INDEX "verification_challenges_email_idx" ON "verification_challenges"("email");

-- CreateIndex
CREATE INDEX "verification_challenges_code_idx" ON "verification_challenges"("code");

-- CreateIndex
CREATE INDEX "verification_challenges_expires_at_idx" ON "verification_challenges"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "app_sessions_refresh_token_key" ON "app_sessions"("refresh_token");

-- CreateIndex
CREATE INDEX "app_sessions_refresh_token_idx" ON "app_sessions"("refresh_token");

-- CreateIndex
CREATE INDEX "app_sessions_expires_at_idx" ON "app_sessions"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "etims_devices_device_id_key" ON "etims_devices"("device_id");

-- CreateIndex
CREATE INDEX "etims_devices_tenant_id_idx" ON "etims_devices"("tenant_id");

-- CreateIndex
CREATE INDEX "etims_devices_device_id_idx" ON "etims_devices"("device_id");

-- CreateIndex
CREATE INDEX "etims_receipts_tenant_id_idx" ON "etims_receipts"("tenant_id");

-- CreateIndex
CREATE INDEX "etims_receipts_kra_receipt_number_idx" ON "etims_receipts"("kra_receipt_number");

-- CreateIndex
CREATE INDEX "etims_receipts_device_id_idx" ON "etims_receipts"("device_id");

-- CreateIndex
CREATE INDEX IF NOT EXISTS "etims_receipts_status_idx" ON "etims_receipts"("status");

-- CreateIndex
CREATE INDEX "etims_receipts_created_at_idx" ON "etims_receipts"("created_at");

-- CreateIndex
CREATE UNIQUE INDEX "etims_receipts_tenant_id_return_number_key" ON "etims_receipts"("tenant_id", "return_number");

-- CreateIndex
CREATE INDEX "etims_z_reports_tenant_id_idx" ON "etims_z_reports"("tenant_id");

-- CreateIndex
CREATE INDEX "etims_z_reports_business_date_idx" ON "etims_z_reports"("business_date");

-- CreateIndex
CREATE UNIQUE INDEX "mpesa_incoming_remote_id_key" ON "mpesa_incoming"("remote_id");

-- CreateIndex
CREATE UNIQUE INDEX "mpesa_incoming_trans_id_key" ON "mpesa_incoming"("trans_id");

-- CreateIndex
CREATE INDEX "mpesa_incoming_tenant_id_received_at_idx" ON "mpesa_incoming"("tenant_id", "received_at");

-- CreateIndex
CREATE INDEX "receipt_links_tenant_id_idx" ON "receipt_links"("tenant_id");

-- CreateIndex
CREATE INDEX "receipt_links_expires_at_idx" ON "receipt_links"("expires_at");

-- CreateIndex
CREATE INDEX "sale_items_tenant_id_idx" ON "sale_items"("tenant_id");

-- CreateIndex
CREATE INDEX "sales_tenant_id_idx" ON "sales"("tenant_id");

-- CreateIndex
CREATE INDEX "sales_created_at_idx" ON "sales"("created_at");

-- AddForeignKey
ALTER TABLE "profiles" ADD CONSTRAINT "profiles_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "products" ADD CONSTRAINT "products_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sales" ADD CONSTRAINT "sales_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "sales"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_adjustments" ADD CONSTRAINT "stock_adjustments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "stock_adjustments" ADD CONSTRAINT "stock_adjustments_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "profiles"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "payments" ADD CONSTRAINT "payments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "deletion_ledgers" ADD CONSTRAINT "deletion_ledgers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "verification_challenges" ADD CONSTRAINT "verification_challenges_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "app_sessions" ADD CONSTRAINT "app_sessions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "etims_devices" ADD CONSTRAINT "etims_devices_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "etims_receipts" ADD CONSTRAINT "etims_receipts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "etims_z_reports" ADD CONSTRAINT "etims_z_reports_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "telemetry_events" ADD CONSTRAINT "telemetry_events_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "churn_snapshots" ADD CONSTRAINT "churn_snapshots_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "support_tickets" ADD CONSTRAINT "support_tickets_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "mpesa_incoming" ADD CONSTRAINT "mpesa_incoming_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "receipt_links" ADD CONSTRAINT "receipt_links_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;
