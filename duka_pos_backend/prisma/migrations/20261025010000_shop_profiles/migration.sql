-- Four authoritative per-shop profiles. Existing shops are Duka by policy.
ALTER TABLE "tenants"
  ADD COLUMN IF NOT EXISTS "business_profile" TEXT NOT NULL DEFAULT 'duka';

ALTER TABLE "tenants"
  DROP CONSTRAINT IF EXISTS "tenants_business_profile_check";

ALTER TABLE "tenants"
  ADD CONSTRAINT "tenants_business_profile_check"
  CHECK ("business_profile" IN ('drinks', 'duka', 'fashion', 'open'));

