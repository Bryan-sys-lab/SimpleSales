-- Authentication V2 foundation: credential metadata, auth audit events, device authorization.

ALTER TABLE profiles ADD COLUMN pin_format TEXT;
ALTER TABLE profiles ADD COLUMN pin_credential_version INTEGER NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN pin_updated_at TEXT;
ALTER TABLE profiles ADD COLUMN pin_failed_attempts INTEGER NOT NULL DEFAULT 0;
ALTER TABLE profiles ADD COLUMN pin_locked_until TEXT;

CREATE TABLE IF NOT EXISTS auth_audit_events (
  id TEXT PRIMARY KEY NOT NULL,
  tenant_id TEXT,
  profile_id TEXT,
  user_id TEXT,
  device_id TEXT,
  event_type TEXT NOT NULL,
  outcome TEXT NOT NULL,
  reason TEXT,
  ip TEXT,
  user_agent TEXT,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_auth_audit_events_tenant_created ON auth_audit_events(tenant_id, created_at);
CREATE INDEX IF NOT EXISTS idx_auth_audit_events_profile_created ON auth_audit_events(profile_id, created_at);
CREATE INDEX IF NOT EXISTS idx_auth_audit_events_type_created ON auth_audit_events(event_type, created_at);

CREATE TABLE IF NOT EXISTS device_authorizations (
  id TEXT PRIMARY KEY NOT NULL,
  tenant_id TEXT NOT NULL,
  profile_id TEXT,
  device_id TEXT NOT NULL,
  label TEXT,
  platform TEXT,
  status TEXT NOT NULL DEFAULT 'active',
  enrolled_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT,
  revoked_at TEXT,
  offline_lease_expires_at TEXT,
  credential_version INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_device_authorizations_tenant_device ON device_authorizations(tenant_id, device_id);
CREATE INDEX IF NOT EXISTS idx_device_authorizations_tenant_profile_status ON device_authorizations(tenant_id, profile_id, status);
CREATE INDEX IF NOT EXISTS idx_device_authorizations_tenant_device_status ON device_authorizations(tenant_id, device_id, status);
