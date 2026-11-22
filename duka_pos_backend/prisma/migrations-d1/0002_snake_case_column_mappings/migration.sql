ALTER TABLE "etims_receipts" RENAME COLUMN "documentType" TO "document_type";
ALTER TABLE "telemetry_events" RENAME COLUMN "deviceId" TO "device_id";
ALTER TABLE "admin_audit_logs" RENAME COLUMN "adminId" TO "admin_id";
ALTER TABLE "admin_audit_logs" RENAME COLUMN "targetType" TO "target_type";
ALTER TABLE "admin_audit_logs" RENAME COLUMN "tenantId" TO "tenant_id";
