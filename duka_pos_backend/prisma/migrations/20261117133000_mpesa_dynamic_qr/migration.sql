ALTER TABLE "tenants"
  ADD COLUMN IF NOT EXISTS "mpesa_qr_cpi" TEXT,
  ADD COLUMN IF NOT EXISTS "mpesa_qr_trx_code" TEXT;

ALTER TABLE "payments"
  ADD COLUMN IF NOT EXISTS "payment_mode" TEXT NOT NULL DEFAULT 'stk',
  ADD COLUMN IF NOT EXISTS "qr_code_data" TEXT;
