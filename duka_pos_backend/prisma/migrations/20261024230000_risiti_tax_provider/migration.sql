ALTER TABLE "tenants"
  ADD COLUMN IF NOT EXISTS "tax_provider" TEXT NOT NULL DEFAULT 'risiti',
  ADD COLUMN IF NOT EXISTS "risiti_merchant_id" TEXT;

UPDATE "tenants"
SET "tax_provider" = 'risiti'
WHERE "tax_provider" IS NULL OR "tax_provider" = '';
