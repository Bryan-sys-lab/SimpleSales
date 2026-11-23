ALTER TABLE "device_diagnostics" RENAME COLUMN "osVersion" TO "os_version";
ALTER TABLE "device_diagnostics" RENAME COLUMN "appVersion" TO "app_version";
ALTER TABLE "device_diagnostics" RENAME COLUMN "buildNumber" TO "build_number";
ALTER TABLE "device_diagnostics" RENAME COLUMN "crashCount" TO "crash_count";
ALTER TABLE "device_diagnostics" RENAME COLUMN "errorCount" TO "error_count";
ALTER TABLE "device_diagnostics" RENAME COLUMN "warningCount" TO "warning_count";
ALTER TABLE "device_crash_entries" RENAME COLUMN "actorName" TO "actor_name";
