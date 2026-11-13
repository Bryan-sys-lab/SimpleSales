-- Device diagnostics: failure reports pushed from till phones so system
-- admins can see what broke, on what phone, under what conditions.

-- ---------------------------------------------------------------
-- device_diagnostics (one row per reporting device)
-- ---------------------------------------------------------------
CREATE TABLE "device_diagnostics" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT,
    "device_id" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "os_version" TEXT NOT NULL,
    "app_version" TEXT NOT NULL,
    "build_number" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "manufacturer" TEXT,
    "model" TEXT,
    "crash_count" INTEGER NOT NULL DEFAULT 0,
    "error_count" INTEGER NOT NULL DEFAULT 0,
    "warning_count" INTEGER NOT NULL DEFAULT 0,
    "first_seen" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "device_diagnostics_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "device_diagnostics_device_id_key" UNIQUE ("device_id"),
    CONSTRAINT "device_diagnostics_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE SET NULL
);

CREATE INDEX "device_diagnostics_device_id_idx" ON "device_diagnostics"("device_id");
CREATE INDEX "device_diagnostics_tenant_id_idx" ON "device_diagnostics"("tenant_id");
CREATE INDEX "device_diagnostics_last_seen_idx" ON "device_diagnostics"("last_seen");

-- ---------------------------------------------------------------
-- device_crash_entries (nested failure entries per diagnostic)
-- ---------------------------------------------------------------
CREATE TABLE "device_crash_entries" (
    "id" TEXT NOT NULL,
    "diagnostic_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "stack" TEXT,
    "route" TEXT,
    "actor_name" TEXT,
    "action" TEXT,
    "breadcrumbs" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "device_crash_entries_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "device_crash_entries_diagnostic_id_fkey" FOREIGN KEY ("diagnostic_id") REFERENCES "device_diagnostics"("id") ON DELETE CASCADE
);

CREATE INDEX "device_crash_entries_diagnostic_id_idx" ON "device_crash_entries"("diagnostic_id");
CREATE INDEX "device_crash_entries_created_at_idx" ON "device_crash_entries"("created_at");
