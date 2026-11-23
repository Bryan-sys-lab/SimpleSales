CREATE TABLE IF NOT EXISTS commercial_consent_grants (
  id TEXT PRIMARY KEY,
  tenant_id TEXT NOT NULL,
  actor_id TEXT NOT NULL,
  actor_role TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'active',
  scopes TEXT NOT NULL DEFAULT '[]',
  notice_version TEXT NOT NULL,
  notice_digest TEXT NOT NULL,
  terms_version TEXT,
  schema_version TEXT NOT NULL,
  dictionary_version TEXT NOT NULL,
  app_version TEXT NOT NULL,
  capture_method TEXT NOT NULL,
  authority_evidence TEXT NOT NULL,
  effective_at TEXT NOT NULL,
  withdrawn_at TEXT,
  processing_state TEXT NOT NULL DEFAULT 'none',
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY (tenant_id) REFERENCES tenants(id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_commercial_consent_grants_tenant_status
  ON commercial_consent_grants(tenant_id, status, effective_at);
