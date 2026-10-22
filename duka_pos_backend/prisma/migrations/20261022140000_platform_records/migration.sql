-- The platform's own records: device telemetry, churn snapshots, what an
-- administrator did, the platform's settings and the shop's support tickets.
--
-- These were lost in an earlier merge of this service. The code that writes
-- them was still here; the tables were not. A route that writes to a table
-- that does not exist is a route that fails at runtime and nowhere else.
--
-- Every statement is guarded, so the migration can be applied to a database
-- that already carries some of these objects.

-- One event from a till phone: route names, feature names and timestamps
-- only. Never secrets, never anything about a person.
CREATE TABLE IF NOT EXISTS "telemetry_events" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT,
    "name" TEXT NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "route" TEXT,
    "detail" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "telemetry_events_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "telemetry_events_tenant_id_idx" ON "telemetry_events"("tenant_id");
CREATE INDEX IF NOT EXISTS "telemetry_events_name_idx" ON "telemetry_events"("name");
CREATE INDEX IF NOT EXISTS "telemetry_events_at_idx" ON "telemetry_events"("at");
CREATE INDEX IF NOT EXISTS "telemetry_events_created_at_idx" ON "telemetry_events"("created_at");

-- A phone's usage, summarised for the day.
CREATE TABLE IF NOT EXISTS "churn_snapshots" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT,
    "date" TIMESTAMP(3) NOT NULL,
    "streak_days" INTEGER NOT NULL,
    "days_since_last_active" INTEGER NOT NULL,
    "total_sessions" INTEGER NOT NULL,
    "risk" TEXT NOT NULL,
    "score" DOUBLE PRECISION NOT NULL,
    "computed_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "churn_snapshots_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "churn_snapshots_tenant_id_idx" ON "churn_snapshots"("tenant_id");
CREATE INDEX IF NOT EXISTS "churn_snapshots_date_idx" ON "churn_snapshots"("date");
CREATE INDEX IF NOT EXISTS "churn_snapshots_computed_at_idx" ON "churn_snapshots"("computed_at");

-- What a platform administrator did, so that "who changed that?" has an
-- answer that is not "ask the server logs".
CREATE TABLE IF NOT EXISTS "admin_audit_logs" (
    "id" TEXT NOT NULL,
    "admin_id" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "target_type" TEXT,
    "target_id" TEXT,
    "tenant_id" TEXT,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "admin_audit_logs_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "admin_audit_logs_admin_id_idx" ON "admin_audit_logs"("admin_id");
CREATE INDEX IF NOT EXISTS "admin_audit_logs_tenant_id_idx" ON "admin_audit_logs"("tenant_id");
CREATE INDEX IF NOT EXISTS "admin_audit_logs_at_idx" ON "admin_audit_logs"("at");

-- A platform setting, by key.
CREATE TABLE IF NOT EXISTS "system_settings" (
    "id" TEXT NOT NULL,
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "description" TEXT,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "system_settings_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "system_settings_key_key" ON "system_settings"("key");

-- A ticket or a request from a shop.
CREATE TABLE IF NOT EXISTS "support_tickets" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "support_tickets_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "support_tickets_tenant_id_idx" ON "support_tickets"("tenant_id");
CREATE INDEX IF NOT EXISTS "support_tickets_type_idx" ON "support_tickets"("type");
CREATE INDEX IF NOT EXISTS "support_tickets_status_idx" ON "support_tickets"("status");
CREATE INDEX IF NOT EXISTS "support_tickets_created_at_idx" ON "support_tickets"("created_at");
