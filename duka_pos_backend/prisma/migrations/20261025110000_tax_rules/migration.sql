CREATE TABLE "tax_rules" (
  "id" TEXT NOT NULL,
  "tax_entity_id" TEXT NOT NULL,
  "tax_type" TEXT NOT NULL,
  "scope" TEXT NOT NULL,
  "jurisdiction" TEXT NOT NULL DEFAULT 'KE',
  "rate_basis_points" INTEGER,
  "tax_base" TEXT NOT NULL,
  "threshold_minor" DECIMAL(65,30),
  "effective_from" TIMESTAMP(3) NOT NULL,
  "effective_to" TIMESTAMP(3),
  "source_url" TEXT NOT NULL,
  "source_reference" TEXT,
  "reviewed_at" TIMESTAMP(3),
  "approved_by" TEXT,
  "approval_note" TEXT,
  "status" TEXT NOT NULL DEFAULT 'needs_review',
  "version" INTEGER NOT NULL DEFAULT 1,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tax_rules_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "tax_rules_tax_entity_id_tax_type_scope_effective_from_effective_to_idx"
  ON "tax_rules"("tax_entity_id", "tax_type", "scope", "effective_from", "effective_to");
CREATE INDEX "tax_rules_status_effective_from_effective_to_idx"
  ON "tax_rules"("status", "effective_from", "effective_to");

ALTER TABLE "tax_rules"
  ADD CONSTRAINT "tax_rules_tax_entity_id_fkey"
  FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities"("id") ON DELETE CASCADE ON UPDATE CASCADE;
