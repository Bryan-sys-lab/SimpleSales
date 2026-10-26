-- M-Pesa Till/Paybill matching, receipt share links, and the credit-note
-- identity on the eTIMS receipt. Additive only.

-- A customer's payment INTO the Till or Paybill, as the server saw it.
CREATE TABLE IF NOT EXISTS "mpesa_incoming" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "remoteId" TEXT NOT NULL,
  "transId" TEXT NOT NULL,
  "amount" DOUBLE PRECISION NOT NULL,
  -- Masked at the callback: first name + last three digits. No full phone
  -- number is ever stored ON THE SERVER either.
  "payerLabel" TEXT NOT NULL,
  "billRef" TEXT,
  "receivedAt" TIMESTAMP(3) NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  -- unclaimed | claimed | ignored | expired
  "status" TEXT NOT NULL DEFAULT 'unclaimed',
  "claimedByDevice" TEXT,
  "claimedSaleUuid" TEXT,
  "claimedAt" TIMESTAMP(3),
  "ignoredAt" TIMESTAMP(3),
  "ignoreReason" TEXT,

  CONSTRAINT "mpesa_incoming_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "mpesa_incoming_remoteId_key" ON "mpesa_incoming"("remoteId");
CREATE UNIQUE INDEX IF NOT EXISTS "mpesa_incoming_transId_key" ON "mpesa_incoming"("transId");
CREATE INDEX IF NOT EXISTS "mpesa_incoming_tenantId_receivedAt_idx" ON "mpesa_incoming"("tenantId", "receivedAt");
CREATE INDEX IF NOT EXISTS "mpesa_incoming_status_idx" ON "mpesa_incoming"("status");

ALTER TABLE "mpesa_incoming"
  ADD CONSTRAINT "mpesa_incoming_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- The public receipt page: token-keyed, revocable, expiring, snapshot-only.
CREATE TABLE IF NOT EXISTS "receipt_links" (
  "id" TEXT NOT NULL,
  "tenantId" TEXT NOT NULL,
  "token" TEXT NOT NULL,
  "snapshot" JSONB NOT NULL,
  "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expiresAt" TIMESTAMP(3) NOT NULL,
  "revokedAt" TIMESTAMP(3),

  CONSTRAINT "receipt_links_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX IF NOT EXISTS "receipt_links_token_key" ON "receipt_links"("token");
CREATE INDEX IF NOT EXISTS "receipt_links_tenantId_idx" ON "receipt_links"("tenantId");
CREATE INDEX IF NOT EXISTS "receipt_links_expiresAt_idx" ON "receipt_links"("expiresAt");

ALTER TABLE "receipt_links"
  ADD CONSTRAINT "receipt_links_tenantId_fkey"
  FOREIGN KEY ("tenantId") REFERENCES "tenants"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- A return queues a CREDIT NOTE through the same table as an invoice, on its
-- own series, carrying the invoice it reverses.
ALTER TABLE "etims_receipts"
  ADD COLUMN IF NOT EXISTS "documentType" TEXT NOT NULL DEFAULT 'invoice',
  ADD COLUMN IF NOT EXISTS "originalReceiptNumber" TEXT,
  ADD COLUMN IF NOT EXISTS "returnNumber" TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS "etims_receipts_tenantId_returnNumber_key"
  ON "etims_receipts"("tenantId", "returnNumber");
