ALTER TABLE "sales" ADD COLUMN IF NOT EXISTS "local_id" INTEGER;

CREATE UNIQUE INDEX IF NOT EXISTS "sales_tenant_id_local_id_key"
  ON "sales"("tenant_id", "local_id")
  WHERE "local_id" IS NOT NULL;

ALTER TABLE "sale_items" ALTER COLUMN "product_id" DROP NOT NULL;
ALTER TABLE "sale_items" DROP CONSTRAINT IF EXISTS "sale_items_product_id_fkey";
ALTER TABLE "sale_items" ADD CONSTRAINT "sale_items_product_id_fkey"
  FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE SET NULL ON UPDATE CASCADE;
