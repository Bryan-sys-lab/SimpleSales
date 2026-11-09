-- Email verification: the table a pending 6-digit code lives in.
--
-- Additive and re-runnable, like every migration in this chain. A shop that
-- never verifies its email pays three nullable columns and one empty table.
--
-- Three decisions worth stating, because all three would be expensive to
-- reverse:
--
--  1. THE PENDING CODE IS NOT A COLUMN ON "tenants". A challenge is
--     single-use, attempt-counted and expires in ten minutes; a shop that
--     fails one attempt must not be left carrying a half-finished
--     verification on its own row. The verified OUTCOME is a column — on
--     "profiles", the row the outcome belongs to — and the challenge is a row
--     of its own that is deleted by time.
--
--  2. THE CODE IS STORED AS AN HMAC, NEVER IN THE CLEAR. `code_hash` is
--     HMAC-SHA256 keyed by a server secret and salted per row, so a dumped
--     table cannot be replayed against `/auth/verify` and a code that leaks
--     in a mailbox cannot be recognised by anything holding the database. The
--     4-digit admin PIN goes through the same transform under the same salt,
--     which is what binds the two halves of the flow to the same person.
--
--  3. INVALIDATION IS "CONSUMED", NOT "DELETED". Every reader of this table
--     asks for `consumed_at IS NULL`, so issuing a new code, burning one after
--     five wrong attempts, and using one successfully all invalidate the
--     outstanding rows the same way — and an audit of what was sent survives,
--     which a delete would take with it.

CREATE TABLE IF NOT EXISTS "email_verifications" (
  "id" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "tenant_id" TEXT,
  "subject" TEXT NOT NULL,
  "code_hash" TEXT NOT NULL,
  "pin_hash" TEXT NOT NULL,
  "salt" TEXT NOT NULL,
  "attempts" INTEGER NOT NULL DEFAULT 0,
  "consumed_at" TIMESTAMP(3),
  "expires_at" TIMESTAMP(3) NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT "email_verifications_pkey" PRIMARY KEY ("id")
);

-- The lookup path: the newest live code for an address.
CREATE INDEX IF NOT EXISTS "email_verifications_email_created_at_idx" ON "email_verifications"("email", "created_at");

-- The renewal housekeeper: rows a sweeper can delete once they are both
-- consumed and expired, without touching anything still live.
CREATE INDEX IF NOT EXISTS "email_verifications_expires_at_idx" ON "email_verifications"("expires_at");

ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "email_verified_at" TIMESTAMP(3);
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "refresh_token_hash" TEXT;
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "refresh_token_expires_at" TIMESTAMP(3);

-- One live refresh token per profile. Postgres permits many NULLs under a
-- unique index, so the profiles that have never signed in with the app are
-- unaffected.
CREATE UNIQUE INDEX IF NOT EXISTS "profiles_refresh_token_hash_key" ON "profiles"("refresh_token_hash");

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'email_verifications_tenant_id_fkey') THEN
    ALTER TABLE "email_verifications" ADD CONSTRAINT "email_verifications_tenant_id_fkey"
      FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
  END IF;
END
$$;
