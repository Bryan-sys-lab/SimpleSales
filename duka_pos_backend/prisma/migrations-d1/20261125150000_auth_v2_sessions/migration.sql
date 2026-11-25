CREATE TABLE IF NOT EXISTS "auth_sessions" (
  "id" TEXT NOT NULL PRIMARY KEY,
  "tenant_id" TEXT,
  "user_id" TEXT,
  "profile_id" TEXT,
  "actor_type" TEXT NOT NULL,
  "device_id" TEXT,
  "refresh_token_hash" TEXT,
  "previous_token_hash" TEXT,
  "issued_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "expires_at" DATETIME,
  "last_seen_at" DATETIME,
  "revoked_at" DATETIME,
  "revoked_reason" TEXT,
  "ip" TEXT,
  "user_agent" TEXT,
  "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "updated_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS "auth_sessions_user_id_revoked_at_idx" ON "auth_sessions"("user_id", "revoked_at");
CREATE INDEX IF NOT EXISTS "auth_sessions_profile_id_revoked_at_idx" ON "auth_sessions"("profile_id", "revoked_at");
CREATE INDEX IF NOT EXISTS "auth_sessions_tenant_id_revoked_at_idx" ON "auth_sessions"("tenant_id", "revoked_at");
CREATE INDEX IF NOT EXISTS "auth_sessions_refresh_token_hash_idx" ON "auth_sessions"("refresh_token_hash");
CREATE INDEX IF NOT EXISTS "auth_sessions_previous_token_hash_idx" ON "auth_sessions"("previous_token_hash");
