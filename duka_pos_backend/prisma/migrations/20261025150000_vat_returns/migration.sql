CREATE TABLE "vat_returns" (
  "id" TEXT NOT NULL,
  "tax_entity_id" TEXT NOT NULL,
  "period_start" TIMESTAMP(3) NOT NULL,
  "period_end" TIMESTAMP(3) NOT NULL,
  "output_vat" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "eligible_input_vat" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "withholding_vat_credit" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "adjustments" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "net_payable" DECIMAL(65,30) NOT NULL DEFAULT 0,
  "evidence" JSONB NOT NULL DEFAULT '{}',
  "status" TEXT NOT NULL DEFAULT 'prepared',
  "submitted_at" TIMESTAMP(3),
  "accepted_at" TIMESTAMP(3),
  "paid_at" TIMESTAMP(3),
  "rejection_reason" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "vat_returns_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "vat_returns_tax_entity_id_period_start_period_end_key"
  ON "vat_returns"("tax_entity_id", "period_start", "period_end");
CREATE INDEX "vat_returns_tax_entity_id_period_start_period_end_idx"
  ON "vat_returns"("tax_entity_id", "period_start", "period_end");
CREATE INDEX "vat_returns_status_idx" ON "vat_returns"("status");

ALTER TABLE "vat_returns"
  ADD CONSTRAINT "vat_returns_tax_entity_id_fkey"
  FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
