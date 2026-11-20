ALTER TABLE "products"
  ADD COLUMN "product_uuid" TEXT,
  ADD COLUMN "item_kind" TEXT NOT NULL DEFAULT 'unknown',
  ADD COLUMN "gpc_code" TEXT,
  ADD COLUMN "gpc_version" TEXT,
  ADD COLUMN "gpc_mapping_status" TEXT NOT NULL DEFAULT 'unmapped',
  ADD COLUMN "gtin" TEXT,
  ADD COLUMN "merchant_sku" TEXT,
  ADD COLUMN "brand_entity_id" TEXT,
  ADD COLUMN "brand_label_local" TEXT,
  ADD COLUMN "manufacturer_entity_id" TEXT,
  ADD COLUMN "variant_attributes" JSONB,
  ADD COLUMN "external_unit_code" TEXT,
  ADD COLUMN "unit_scheme" TEXT,
  ADD COLUMN "unit_version" TEXT,
  ADD COLUMN "unit_mapping_status" TEXT NOT NULL DEFAULT 'unknown',
  ADD COLUMN "pack_quantity" DECIMAL(18,6),
  ADD COLUMN "pack_unit_code" TEXT,
  ADD COLUMN "identity_provenance" TEXT NOT NULL DEFAULT 'system_derived';

CREATE INDEX "products_item_kind_gpc_mapping_status_idx"
  ON "products"("item_kind", "gpc_mapping_status");

CREATE UNIQUE INDEX "products_tenant_id_product_uuid_key"
  ON "products"("tenant_id", "product_uuid");
