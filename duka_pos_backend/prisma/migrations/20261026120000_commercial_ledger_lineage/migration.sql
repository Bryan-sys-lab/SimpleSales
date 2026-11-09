ALTER TABLE "commercial_contributions"
  ADD COLUMN "status" TEXT NOT NULL DEFAULT 'accepted',
  ADD COLUMN "consent_purpose_version" TEXT NOT NULL DEFAULT 'commercial-intelligence-v1',
  ADD COLUMN "quality_flags" JSONB NOT NULL DEFAULT '[]',
  ADD COLUMN "payload_checksum" TEXT NOT NULL DEFAULT '',
  ADD COLUMN "supersedes_record_id" TEXT,
  ADD COLUMN "retention_state" TEXT NOT NULL DEFAULT 'active',
  ADD COLUMN "deleted_at" TIMESTAMP(3);

CREATE INDEX "commercial_contributions_status_accepted_at_idx"
  ON "commercial_contributions" ("status", "accepted_at");
