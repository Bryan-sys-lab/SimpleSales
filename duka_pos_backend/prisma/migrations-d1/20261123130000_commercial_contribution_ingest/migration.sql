ALTER TABLE "commercial_contributions" ADD COLUMN "tenant_id" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "commercial_contributions_tenant_batch_key"
  ON "commercial_contributions"("tenant_id", "batch_id");
