CREATE TABLE IF NOT EXISTS "admin_keys" (
  "id" TEXT NOT NULL,
  "email" TEXT NOT NULL,
  "phone" TEXT NOT NULL,
  "key_hash" TEXT NOT NULL,
  "created_by" TEXT NOT NULL,
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "used_at" TIMESTAMP(3),
  "expires_at" TIMESTAMP(3) NOT NULL,
  "revoked_at" TIMESTAMP(3),
  CONSTRAINT "admin_keys_pkey" PRIMARY KEY ("id")
);

DROP INDEX IF EXISTS "admin_keys_email_phone_key";
CREATE INDEX IF NOT EXISTS "admin_keys_email_phone_idx" ON "admin_keys"("email", "phone");
CREATE INDEX IF NOT EXISTS "admin_keys_email_idx" ON "admin_keys"("email");
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "department" TEXT NOT NULL DEFAULT 'operations';
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "role" TEXT NOT NULL DEFAULT 'worker';
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "permissions" JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "can_recruit" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "can_mint_keys" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "can_assign_tasks" BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE "admin_keys" ADD COLUMN IF NOT EXISTS "parent_key_id" TEXT;
CREATE INDEX IF NOT EXISTS "admin_keys_parent_key_id_idx" ON "admin_keys"("parent_key_id");
DO $$ BEGIN
  ALTER TABLE "admin_keys" ADD CONSTRAINT "admin_keys_parent_key_id_fkey"
    FOREIGN KEY ("parent_key_id") REFERENCES "admin_keys"("id") ON DELETE SET NULL ON UPDATE CASCADE;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

CREATE TABLE IF NOT EXISTS "admin_tasks" (
  "id" TEXT NOT NULL,
  "title" TEXT NOT NULL,
  "description" TEXT,
  "department" TEXT NOT NULL,
  "status" TEXT NOT NULL DEFAULT 'assigned',
  "created_by" TEXT NOT NULL,
  "assignee_key_id" TEXT NOT NULL,
  "due_at" TIMESTAMP(3),
  "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" TIMESTAMP(3) NOT NULL,
  CONSTRAINT "admin_tasks_pkey" PRIMARY KEY ("id"),
  CONSTRAINT "admin_tasks_assignee_key_id_fkey" FOREIGN KEY ("assignee_key_id") REFERENCES "admin_keys"("id") ON DELETE RESTRICT ON UPDATE CASCADE
);
CREATE INDEX IF NOT EXISTS "admin_tasks_assignee_key_id_status_idx" ON "admin_tasks"("assignee_key_id", "status");
CREATE INDEX IF NOT EXISTS "admin_tasks_department_created_at_idx" ON "admin_tasks"("department", "created_at");

ALTER TABLE "telemetry_events" ADD COLUMN IF NOT EXISTS "session_jti" TEXT;
CREATE INDEX IF NOT EXISTS "telemetry_events_session_jti_at_idx" ON "telemetry_events"("session_jti", "at");
ALTER TABLE "telemetry_events" ADD COLUMN IF NOT EXISTS "client_event_id" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "telemetry_events_client_event_id_key" ON "telemetry_events"("client_event_id");

-- Legacy AppSession rows are not used for authentication. Revoke and erase
-- their plaintext bearer material rather than allowing historical sessions
-- to remain a credential store.
UPDATE "app_sessions" SET "access_token" = '[redacted]', "refresh_token" = 'revoked:' || "id";
ALTER TABLE "device_crash_entries" ADD COLUMN IF NOT EXISTS "session_jti" TEXT;
CREATE INDEX IF NOT EXISTS "device_crash_entries_session_jti_idx" ON "device_crash_entries"("session_jti");
ALTER TABLE "device_crash_entries" ADD COLUMN IF NOT EXISTS "client_event_id" TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS "device_crash_entries_diagnostic_id_client_event_id_key" ON "device_crash_entries"("diagnostic_id", "client_event_id");
