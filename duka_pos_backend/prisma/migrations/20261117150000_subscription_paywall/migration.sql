CREATE TABLE "tenant_subscriptions" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending',
  "price_minor" INTEGER,
  "currency" TEXT NOT NULL DEFAULT 'KES',
  "billing_interval" TEXT NOT NULL DEFAULT 'monthly',
  "current_period_end" TIMESTAMP(3),
  "grace_until" TIMESTAMP(3),
  "voucher_id" TEXT,
  "updated_by" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tenant_subscriptions_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "tenant_subscriptions_tenant_id_key" ON "tenant_subscriptions"("tenant_id");
CREATE UNIQUE INDEX "tenant_subscriptions_voucher_id_key" ON "tenant_subscriptions"("voucher_id");
CREATE INDEX "tenant_subscriptions_status_current_period_end_idx" ON "tenant_subscriptions"("status", "current_period_end");

CREATE TABLE "access_vouchers" (
  "id" TEXT NOT NULL,
  "code_hash" TEXT NOT NULL,
  "code_prefix" TEXT NOT NULL,
  "tenant_id" TEXT,
  "issued_to_profile_id" TEXT,
  "issued_to_email" TEXT,
  "expires_at" TIMESTAMP(3),
  "redeemed_at" TIMESTAMP(3),
  "redeemed_by_profile_id" TEXT,
  "revoked_at" TIMESTAMP(3),
  "paused_at" TIMESTAMP(3),
  "deleted_at" TIMESTAMP(3),
  "auto_issued" BOOLEAN NOT NULL DEFAULT false,
  "created_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "access_vouchers_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "access_vouchers_code_hash_key" ON "access_vouchers"("code_hash");
CREATE INDEX "access_vouchers_tenant_id_expires_at_idx" ON "access_vouchers"("tenant_id", "expires_at");
CREATE INDEX "access_vouchers_issued_to_email_idx" ON "access_vouchers"("issued_to_email");

ALTER TABLE "tenant_subscriptions" ADD CONSTRAINT "tenant_subscriptions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "tenant_subscriptions" ADD CONSTRAINT "tenant_subscriptions_voucher_id_fkey" FOREIGN KEY ("voucher_id") REFERENCES "access_vouchers"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "access_vouchers" ADD CONSTRAINT "access_vouchers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "access_vouchers" ADD CONSTRAINT "access_vouchers_issued_to_profile_id_fkey" FOREIGN KEY ("issued_to_profile_id") REFERENCES "profiles"("id") ON DELETE SET NULL ON UPDATE CASCADE;
ALTER TABLE "access_vouchers" ADD CONSTRAINT "access_vouchers_redeemed_by_profile_id_fkey" FOREIGN KEY ("redeemed_by_profile_id") REFERENCES "profiles"("id") ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE "subscription_payments" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "reference" TEXT NOT NULL,
  "phone_number" TEXT NOT NULL,
  "amount_minor" INTEGER NOT NULL,
  "duration_months" INTEGER NOT NULL DEFAULT 1,
  "status" TEXT NOT NULL DEFAULT 'PENDING',
  "checkout_request_id" TEXT,
  "provider_status" TEXT,
  "mpesa_receipt_code" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "subscription_payments_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "subscription_payments_reference_key" ON "subscription_payments"("reference");
CREATE INDEX "subscription_payments_tenant_id_status_idx" ON "subscription_payments"("tenant_id", "status");
ALTER TABLE "subscription_payments" ADD CONSTRAINT "subscription_payments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
