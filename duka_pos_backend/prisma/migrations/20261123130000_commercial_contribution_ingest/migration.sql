ALTER TABLE "commercial_contributions" ADD COLUMN "tenant_id" TEXT;
CREATE UNIQUE INDEX "commercial_contributions_tenant_batch_key"
  ON "commercial_contributions"("tenant_id", "batch_id");
