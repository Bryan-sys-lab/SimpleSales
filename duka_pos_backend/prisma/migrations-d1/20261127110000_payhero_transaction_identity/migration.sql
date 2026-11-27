ALTER TABLE "payments"
  ADD COLUMN "provider_reference" TEXT;

ALTER TABLE "subscription_payments"
  ADD COLUMN "provider_reference" TEXT;

CREATE TABLE "payhero_channel_registrations" (
  "fingerprint" TEXT NOT NULL PRIMARY KEY,
  "tenant_id" TEXT,
  "channel_type" TEXT NOT NULL,
  "short_code" TEXT NOT NULL,
  "account_number" TEXT NOT NULL DEFAULT '',
  "status" TEXT NOT NULL DEFAULT 'REGISTERING',
  "channel_id" INTEGER,
  "created_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "payhero_channel_registrations_tenant_id_fkey"
    FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE UNIQUE INDEX "payhero_channel_registrations_channel_id_key"
  ON "payhero_channel_registrations" ("channel_id");

CREATE INDEX "payhero_channel_registrations_tenant_id_status_idx"
  ON "payhero_channel_registrations" ("tenant_id", "status");
