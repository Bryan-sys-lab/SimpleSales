ALTER TABLE "tenant_subscriptions"
ADD COLUMN "discount_percent" INTEGER NOT NULL DEFAULT 0;

ALTER TABLE "access_vouchers"
ADD COLUMN "duration_months" INTEGER NOT NULL DEFAULT 1;

ALTER TABLE "subscription_payments"
ADD COLUMN "discount_percent" INTEGER NOT NULL DEFAULT 0;
