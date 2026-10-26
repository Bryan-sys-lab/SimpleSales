CREATE TABLE "tax_entities" (
  "id" TEXT NOT NULL,
  "legal_form" TEXT NOT NULL,
  "display_label" TEXT NOT NULL,
  "kra_pin_ciphertext" TEXT,
  "kra_pin_last4" TEXT,
  "registered_tax_obligations" JSONB NOT NULL DEFAULT '[]',
  "accounting_period_start_month" INTEGER NOT NULL DEFAULT 1,
  "status" TEXT NOT NULL DEFAULT 'needs_review',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "tax_entities_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "shop_tax_entities" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "tax_entity_id" TEXT NOT NULL,
  "outlet_reference" TEXT,
  "effective_from" TIMESTAMP(3) NOT NULL,
  "effective_to" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "shop_tax_entities_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "shop_tax_entities_tenant_id_effective_from_effective_to_idx"
  ON "shop_tax_entities"("tenant_id", "effective_from", "effective_to");
CREATE INDEX "shop_tax_entities_tax_entity_id_effective_from_effective_to_idx"
  ON "shop_tax_entities"("tax_entity_id", "effective_from", "effective_to");

ALTER TABLE "shop_tax_entities"
  ADD CONSTRAINT "shop_tax_entities_tenant_id_fkey"
  FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "shop_tax_entities"
  ADD CONSTRAINT "shop_tax_entities_tax_entity_id_fkey"
  FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities"("id") ON DELETE CASCADE ON UPDATE CASCADE;
