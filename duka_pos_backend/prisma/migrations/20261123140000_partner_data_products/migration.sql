CREATE TABLE "partners" (
  "id" TEXT NOT NULL,
  "legal_name" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'pending_contract',
  "contract_ref" TEXT,
  "purpose" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "partners_pkey" PRIMARY KEY ("id")
);

CREATE TABLE "partner_grants" (
  "id" TEXT NOT NULL,
  "partner_id" TEXT NOT NULL,
  "product_id" TEXT NOT NULL,
  "snapshot_id" TEXT NOT NULL,
  "permitted_scope" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active',
  "expires_at" TIMESTAMP(3) NOT NULL,
  "quota_per_day" INTEGER NOT NULL DEFAULT 100,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "revoked_at" TIMESTAMP(3),
  CONSTRAINT "partner_grants_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "partner_grants_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "partners"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE "partner_credentials" (
  "id" TEXT NOT NULL,
  "partner_id" TEXT NOT NULL,
  "key_prefix" TEXT NOT NULL,
  "key_hash" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'active',
  "expires_at" TIMESTAMP(3) NOT NULL,
  "quota_per_day" INTEGER NOT NULL DEFAULT 100,
  "revoked_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "partner_credentials_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "partner_credentials_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "partners"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "partner_credentials_key_hash_key" ON "partner_credentials"("key_hash");

CREATE TABLE "partner_deliveries" (
  "id" TEXT NOT NULL,
  "partner_id" TEXT NOT NULL,
  "grant_id" TEXT NOT NULL,
  "snapshot_id" TEXT NOT NULL,
  "product_id" TEXT NOT NULL,
  "status" TEXT NOT NULL,
  "response_hash" TEXT,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "partner_deliveries_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "partner_deliveries_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "partners"("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "partner_deliveries_grant_id_fkey" FOREIGN KEY ("grant_id") REFERENCES "partner_grants"("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE INDEX "partner_grants_partner_id_status_expires_at_idx" ON "partner_grants"("partner_id", "status", "expires_at");
CREATE INDEX "partner_credentials_partner_id_status_expires_at_idx" ON "partner_credentials"("partner_id", "status", "expires_at");
CREATE INDEX "partner_deliveries_partner_id_created_at_idx" ON "partner_deliveries"("partner_id", "created_at");
