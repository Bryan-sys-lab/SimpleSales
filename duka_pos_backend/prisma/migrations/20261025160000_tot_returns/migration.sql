CREATE TABLE "tot_returns" (
  "id" TEXT NOT NULL,
  "tax_entity_id" TEXT NOT NULL,
  "period_start" TIMESTAMP(3) NOT NULL,
  "period_end" TIMESTAMP(3) NOT NULL,
  "gross_sales" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "rate_basis_points" INTEGER,
  "estimate" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "evidence" JSONB NOT NULL DEFAULT '{}',
  "status" TEXT NOT NULL DEFAULT 'prepared',
  "submitted_at" TIMESTAMP(3),
  "accepted_at" TIMESTAMP(3),
  "paid_at" TIMESTAMP(3),
  "rejection_reason" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tot_returns_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "tot_returns_tax_entity_id_period_start_period_end_key"
  ON "tot_returns"("tax_entity_id", "period_start", "period_end");
CREATE INDEX "tot_returns_tax_entity_id_period_start_period_end_idx"
  ON "tot_returns"("tax_entity_id", "period_start", "period_end");
CREATE INDEX "tot_returns_status_idx" ON "tot_returns"("status");

ALTER TABLE "tot_returns"
  ADD CONSTRAINT "tot_returns_tax_entity_id_fkey"
  FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
