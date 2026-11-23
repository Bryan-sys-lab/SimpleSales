CREATE TABLE IF NOT EXISTS partners (
  id TEXT PRIMARY KEY,
  legal_name TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending_contract',
  contract_ref TEXT,
  purpose TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS partner_grants (
  id TEXT PRIMARY KEY,
  partner_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  snapshot_id TEXT NOT NULL,
  permitted_scope TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  expires_at TEXT NOT NULL,
  quota_per_day INTEGER NOT NULL DEFAULT 100,
  created_at TEXT NOT NULL,
  revoked_at TEXT,
  FOREIGN KEY(partner_id) REFERENCES partners(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS partner_credentials (
  id TEXT PRIMARY KEY,
  partner_id TEXT NOT NULL,
  key_prefix TEXT NOT NULL,
  key_hash TEXT NOT NULL UNIQUE,
  status TEXT NOT NULL DEFAULT 'active',
  expires_at TEXT NOT NULL,
  quota_per_day INTEGER NOT NULL DEFAULT 100,
  revoked_at TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(partner_id) REFERENCES partners(id) ON DELETE CASCADE
);
CREATE TABLE IF NOT EXISTS partner_deliveries (
  id TEXT PRIMARY KEY,
  partner_id TEXT NOT NULL,
  grant_id TEXT NOT NULL,
  snapshot_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  status TEXT NOT NULL,
  response_hash TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(partner_id) REFERENCES partners(id) ON DELETE CASCADE,
  FOREIGN KEY(grant_id) REFERENCES partner_grants(id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_partner_grants_partner_status ON partner_grants(partner_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_partner_credentials_partner_status ON partner_credentials(partner_id, status, expires_at);
CREATE INDEX IF NOT EXISTS idx_partner_deliveries_partner_created ON partner_deliveries(partner_id, created_at);
