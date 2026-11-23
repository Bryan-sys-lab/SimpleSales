CREATE TABLE "commercial_consent_grants" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "actor_id" TEXT NOT NULL,
  "actor_role" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active',
  "scopes" JSONB NOT NULL,
  "notice_version" TEXT NOT NULL,
  "notice_digest" TEXT NOT NULL,
  "terms_version" TEXT,
  "schema_version" TEXT NOT NULL,
  "dictionary_version" TEXT NOT NULL,
  "app_version" TEXT NOT NULL,
  "capture_method" TEXT NOT NULL,
  "authority_evidence" TEXT NOT NULL,
  "effective_at" TIMESTAMP(3) NOT NULL,
  "withdrawn_at" TIMESTAMP(3),
  "processing_state" TEXT NOT NULL DEFAULT 'none',
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "commercial_consent_grants_tenant_id_fkey"
    FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "commercial_consent_grants_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "commercial_consent_grants_tenant_id_status_effective_at_idx"
  ON "commercial_consent_grants"("tenant_id", "status", "effective_at");
