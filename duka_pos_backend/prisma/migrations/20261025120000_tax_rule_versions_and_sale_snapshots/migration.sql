ALTER TABLE "tax_rules" ADD COLUMN IF NOT EXISTS "version" INTEGER NOT NULL DEFAULT 1;

ALTER TABLE "sale_items"
  ADD COLUMN "tax_class" TEXT,
  ADD COLUMN "vat_rate_bps" INTEGER,
  ADD COLUMN "tax_rule_id" TEXT,
  ADD COLUMN "tax_rule_version" INTEGER;

CREATE INDEX "sale_items_tax_rule_id_idx" ON "sale_items"("tax_rule_id");

ALTER TABLE "sale_items"
  ADD CONSTRAINT "sale_items_tax_rule_id_fkey"
  FOREIGN KEY ("tax_rule_id") REFERENCES "tax_rules"("id") ON DELETE SET NULL ON UPDATE CASCADE;
