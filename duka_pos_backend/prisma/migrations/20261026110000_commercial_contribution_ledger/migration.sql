CREATE TABLE "commercial_contributions" (
    "id" TEXT NOT NULL,
    "batch_id" TEXT NOT NULL,
    "record_id" TEXT NOT NULL,
    "policy_version" TEXT NOT NULL,
    "schema_version" TEXT NOT NULL,
    "business_profile" TEXT NOT NULL,
    "period_start" TIMESTAMP(3) NOT NULL,
    "period_end" TIMESTAMP(3) NOT NULL,
    "currency" TEXT NOT NULL,
    "category_family" TEXT NOT NULL,
    "unit_kind" TEXT NOT NULL,
    "transaction_count" INTEGER NOT NULL,
    "gross_revenue_minor" INTEGER NOT NULL,
    "discount_minor" INTEGER NOT NULL,
    "refund_minor" INTEGER NOT NULL,
    "cogs_minor" INTEGER NOT NULL,
    "stockout_count" INTEGER NOT NULL,
    "payment_method_mix" JSONB NOT NULL,
    "coverage_level" TEXT NOT NULL,
    "normalized_version" TEXT NOT NULL,
    "aggregation_job_version" TEXT,
    "dataset_snapshot_id" TEXT,
    "partner_export_refs" JSONB NOT NULL DEFAULT '[]',
    "accepted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "commercial_contributions_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "commercial_contributions_record_id_key"
    ON "commercial_contributions"("record_id");
CREATE INDEX "commercial_contributions_business_profile_period_start_period_end_idx"
    ON "commercial_contributions"("business_profile", "period_start", "period_end");
CREATE INDEX "commercial_contributions_batch_id_accepted_at_idx"
    ON "commercial_contributions"("batch_id", "accepted_at");
