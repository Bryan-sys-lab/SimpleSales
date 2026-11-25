ALTER TABLE "admin_keys" ADD COLUMN "failed_attempts" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "admin_keys" ADD COLUMN "locked_until" DATETIME;
