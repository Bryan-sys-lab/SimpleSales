ALTER TABLE "payments"
  ADD COLUMN IF NOT EXISTS "provider_status" TEXT,
  ADD COLUMN IF NOT EXISTS "provider_checked_at" TIMESTAMP(3);
