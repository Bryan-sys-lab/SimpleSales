CREATE TABLE "business_context" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "app_profile" TEXT NOT NULL,
  "primary_activity_code" TEXT,
  "primary_activity_status" TEXT NOT NULL DEFAULT 'pending',
  "activity_scheme" TEXT,
  "activity_version" TEXT,
  "secondary_activity_codes" JSONB NOT NULL DEFAULT '[]',
  "operator_roles" JSONB NOT NULL DEFAULT '[]',
  "sales_channels" JSONB NOT NULL DEFAULT '[]',
  "county_code" TEXT,
  "settlement_context" TEXT NOT NULL DEFAULT 'unknown',
  "field_provenance" JSONB NOT NULL DEFAULT '{}',
  "confirmed_at" TIMESTAMP(3),
  "schema_version" INTEGER NOT NULL DEFAULT 1,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "business_context_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "business_context_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "business_context_tenant_id_key" ON "business_context"("tenant_id");
CREATE INDEX "business_context_primary_activity_code_idx" ON "business_context"("primary_activity_code");
