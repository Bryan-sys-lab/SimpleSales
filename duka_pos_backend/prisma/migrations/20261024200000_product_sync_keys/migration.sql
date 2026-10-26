ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "sync_key" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "products_tenant_id_sync_key_key"
  ON "products"("tenant_id", "sync_key");
