CREATE TABLE "membership_requests" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "tenant_id" TEXT NOT NULL,
  "requested_by" TEXT NOT NULL,
  "features" TEXT NOT NULL DEFAULT '[]',
  "requirements" TEXT NOT NULL DEFAULT '',
  "status" TEXT NOT NULL DEFAULT 'pending',
  "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "membership_requests_tenant_id_fkey"
    FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "membership_requests_tenant_id_created_at_idx" ON "membership_requests"("tenant_id", "created_at");
CREATE INDEX "membership_requests_status_updated_at_idx" ON "membership_requests"("status", "updated_at");

CREATE TABLE "membership_offers" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "request_id" TEXT NOT NULL,
  "revision" INTEGER NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'offered',
  "amount_minor" INTEGER NOT NULL,
  "currency" TEXT NOT NULL DEFAULT 'KES',
  "term_months" INTEGER,
  "payment_arrangement" TEXT NOT NULL,
  "renewal_terms" TEXT NOT NULL,
  "included_features" TEXT NOT NULL DEFAULT '[]',
  "additional_conditions" TEXT,
  "expires_at" DATETIME,
  "created_by" TEXT NOT NULL,
  "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "membership_offers_request_id_fkey"
    FOREIGN KEY ("request_id") REFERENCES "membership_requests" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "membership_offers_request_id_revision_key" UNIQUE ("request_id", "revision")
);
CREATE INDEX "membership_offers_request_id_created_at_idx" ON "membership_offers"("request_id", "created_at");
CREATE INDEX "membership_offers_request_id_status_idx" ON "membership_offers"("request_id", "status");

CREATE TABLE "membership_messages" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "request_id" TEXT NOT NULL,
  "sender_type" TEXT NOT NULL,
  "sender_id" TEXT NOT NULL,
  "body" TEXT NOT NULL,
  "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "membership_messages_request_id_fkey"
    FOREIGN KEY ("request_id") REFERENCES "membership_requests" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE INDEX "membership_messages_request_id_created_at_idx" ON "membership_messages"("request_id", "created_at");

CREATE TABLE "membership_agreements" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "tenant_id" TEXT NOT NULL,
  "request_id" TEXT NOT NULL,
  "offer_id" TEXT NOT NULL,
  "reference" TEXT NOT NULL,
  "snapshot" TEXT NOT NULL,
  "accepted_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "membership_agreements_tenant_id_fkey"
    FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "membership_agreements_request_id_fkey"
    FOREIGN KEY ("request_id") REFERENCES "membership_requests" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT "membership_agreements_offer_id_fkey"
    FOREIGN KEY ("offer_id") REFERENCES "membership_offers" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "membership_agreements_request_id_key" ON "membership_agreements"("request_id");
CREATE UNIQUE INDEX "membership_agreements_offer_id_key" ON "membership_agreements"("offer_id");
CREATE UNIQUE INDEX "membership_agreements_reference_key" ON "membership_agreements"("reference");
CREATE INDEX "membership_agreements_tenant_id_accepted_at_idx" ON "membership_agreements"("tenant_id", "accepted_at");

CREATE TRIGGER "membership_accepted_offer_immutable"
BEFORE UPDATE OF
  "revision", "amount_minor", "currency", "term_months", "payment_arrangement",
  "renewal_terms", "included_features", "additional_conditions", "expires_at"
ON "membership_offers"
WHEN EXISTS (
  SELECT 1 FROM "membership_agreements" WHERE "offer_id" = OLD."id"
)
BEGIN
  SELECT RAISE(ABORT, 'Accepted membership offer terms are immutable');
END;

CREATE TRIGGER "membership_agreements_immutable"
BEFORE UPDATE ON "membership_agreements"
BEGIN
  SELECT RAISE(ABORT, 'Accepted membership agreements are immutable');
END;

ALTER TABLE "tenant_subscriptions"
  ADD COLUMN "agreement_id" TEXT REFERENCES "membership_agreements"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE UNIQUE INDEX "tenant_subscriptions_agreement_id_key" ON "tenant_subscriptions"("agreement_id");

ALTER TABLE "subscription_payments"
  ADD COLUMN "agreement_id" TEXT REFERENCES "membership_agreements"("id") ON DELETE SET NULL ON UPDATE CASCADE;
CREATE INDEX "subscription_payments_agreement_id_idx" ON "subscription_payments"("agreement_id");
CREATE UNIQUE INDEX "subscription_payments_one_pending_agreement_idx"
  ON "subscription_payments"("agreement_id")
  WHERE "agreement_id" IS NOT NULL AND "status" = 'PENDING';

ALTER TABLE "subscription_payments"
  ADD COLUMN "voucher_applied" INTEGER NOT NULL DEFAULT 1;
