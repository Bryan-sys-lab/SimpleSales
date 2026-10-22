ALTER TABLE "profiles" DROP CONSTRAINT IF EXISTS "profiles_oidc_subject_key";
CREATE INDEX IF NOT EXISTS "profiles_oidc_subject_idx" ON "profiles"("oidc_subject");
ALTER TABLE "products" ALTER COLUMN "stock_qty" TYPE DECIMAL(12,3) USING "stock_qty"::DECIMAL;
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "bottle_ml" INTEGER NOT NULL DEFAULT 750;
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "half_price" DECIMAL(12,2);
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "quarter_price" DECIMAL(12,2);
ALTER TABLE "sale_items" ALTER COLUMN "qty" TYPE DECIMAL(12,3) USING "qty"::DECIMAL;
ALTER TABLE "sale_items" ADD COLUMN IF NOT EXISTS "portion" TEXT NOT NULL DEFAULT 'full';
ALTER TABLE "sale_items" ADD COLUMN IF NOT EXISTS "portion_ml" INTEGER NOT NULL DEFAULT 0;
