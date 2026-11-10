-- Create Open profile job / cost-pool tables and Fashion variant table
-- These back the multi-device sync endpoints called by the till app.

-- ---------------------------------------------------------------
-- product_variants (Fashion size/colour/SKU variants)
-- ---------------------------------------------------------------
CREATE TABLE "product_variants" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "product_id" TEXT NOT NULL,
    "variant_name" TEXT NOT NULL DEFAULT '',
    "sku" TEXT NOT NULL DEFAULT '',
    "unit" TEXT NOT NULL DEFAULT 'each',
    "size_ml" INTEGER NOT NULL DEFAULT 0,
    "sell_price" DECIMAL(65,30) NOT NULL DEFAULT 0,
    "cost_price" DECIMAL(65,30) NOT NULL DEFAULT 0,
    "stock_qty" DECIMAL(65,30) NOT NULL DEFAULT 0,
    "reserved_qty" DECIMAL(65,30) NOT NULL DEFAULT 0,
    "reorder_level" INTEGER NOT NULL DEFAULT 0,
    "position" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "product_variants_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE,
    CONSTRAINT "product_variants_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "product_variants_tenant_id_sync_key_key" ON "product_variants"("tenant_id", "sync_key");
CREATE UNIQUE INDEX "product_variants_tenant_id_product_id_local_id_key" ON "product_variants"("tenant_id", "product_id", "local_id");
CREATE INDEX "product_variants_tenant_id_idx" ON "product_variants"("tenant_id");
CREATE INDEX "product_variants_product_id_idx" ON "product_variants"("product_id");

-- ---------------------------------------------------------------
-- jobs (Open profile service work orders)
-- ---------------------------------------------------------------
CREATE TABLE "jobs" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "uuid" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "customer_name" TEXT,
    "customer_phone" TEXT,
    "quote_minor" INTEGER NOT NULL DEFAULT 0,
    "final_price_minor" INTEGER,
    "status" TEXT NOT NULL DEFAULT 'draft',
    "due_at" TIMESTAMP(3),
    "cost_pool_id" TEXT,
    "staff_id" TEXT NOT NULL,
    "staff_name" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "jobs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "jobs_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "jobs_tenant_id_sync_key_key" ON "jobs"("tenant_id", "sync_key");
CREATE UNIQUE INDEX "jobs_tenant_id_uuid_key" ON "jobs"("tenant_id", "uuid");
CREATE INDEX "jobs_tenant_id_idx" ON "jobs"("tenant_id");
CREATE INDEX "jobs_status_idx" ON "jobs"("status");
CREATE INDEX "jobs_cost_pool_id_idx" ON "jobs"("cost_pool_id");

-- ---------------------------------------------------------------
-- cost_pools (Open profile shared cost recovery pools)
-- ---------------------------------------------------------------
CREATE TABLE "cost_pools" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "uuid" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "pool_type" TEXT NOT NULL DEFAULT 'lot',
    "invested_minor" INTEGER NOT NULL DEFAULT 0,
    "recovered_minor" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'open',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "cost_pools_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "cost_pools_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "cost_pools_tenant_id_sync_key_key" ON "cost_pools"("tenant_id", "sync_key");
CREATE UNIQUE INDEX "cost_pools_tenant_id_uuid_key" ON "cost_pools"("tenant_id", "uuid");
CREATE INDEX "cost_pools_tenant_id_idx" ON "cost_pools"("tenant_id");
CREATE INDEX "cost_pools_status_idx" ON "cost_pools"("status");

-- ---------------------------------------------------------------
-- job_costs (Open profile job cost lines)
-- ---------------------------------------------------------------
CREATE TABLE "job_costs" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "uuid" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "type" TEXT NOT NULL,
    "amount_minor" INTEGER NOT NULL,
    "payment_method" TEXT NOT NULL DEFAULT 'cash',
    "reference" TEXT,
    "staff_id" TEXT,
    "staff_name" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "job_costs_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "job_costs_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE,
    CONSTRAINT "job_costs_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "jobs"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "job_costs_tenant_id_sync_key_key" ON "job_costs"("tenant_id", "sync_key");
CREATE UNIQUE INDEX "job_costs_tenant_id_job_id_local_id_key" ON "job_costs"("tenant_id", "job_id", "local_id");
CREATE INDEX "job_costs_tenant_id_idx" ON "job_costs"("tenant_id");
CREATE INDEX "job_costs_job_id_idx" ON "job_costs"("job_id");

-- ---------------------------------------------------------------
-- job_payments (Open profile job payment lines)
-- ---------------------------------------------------------------
CREATE TABLE "job_payments" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "uuid" TEXT NOT NULL,
    "job_id" TEXT NOT NULL,
    "amount_minor" INTEGER NOT NULL,
    "payment_method" TEXT NOT NULL,
    "reference" TEXT,
    "staff_id" TEXT,
    "staff_name" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "job_payments_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "job_payments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE,
    CONSTRAINT "job_payments_job_id_fkey" FOREIGN KEY ("job_id") REFERENCES "jobs"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "job_payments_tenant_id_sync_key_key" ON "job_payments"("tenant_id", "sync_key");
CREATE UNIQUE INDEX "job_payments_tenant_id_job_id_local_id_key" ON "job_payments"("tenant_id", "job_id", "local_id");
CREATE INDEX "job_payments_tenant_id_idx" ON "job_payments"("tenant_id");
CREATE INDEX "job_payments_job_id_idx" ON "job_payments"("job_id");

-- ---------------------------------------------------------------
-- owner_transactions (Open profile capital/drawing/loan)
-- ---------------------------------------------------------------
CREATE TABLE "owner_transactions" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "uuid" TEXT NOT NULL,
    "transaction_type" TEXT NOT NULL,
    "amount_minor" INTEGER NOT NULL,
    "shift_id" INTEGER,
    "staff_id" TEXT,
    "staff_name" TEXT NOT NULL,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "owner_transactions_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "owner_transactions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE
);

CREATE UNIQUE INDEX "owner_transactions_tenant_id_sync_key_key" ON "owner_transactions"("tenant_id", "sync_key");
CREATE UNIQUE INDEX "owner_transactions_tenant_id_uuid_key" ON "owner_transactions"("tenant_id", "uuid");
CREATE INDEX "owner_transactions_tenant_id_idx" ON "owner_transactions"("tenant_id");
CREATE INDEX "owner_transactions_transaction_type_idx" ON "owner_transactions"("transaction_type");
CREATE INDEX "owner_transactions_created_at_idx" ON "owner_transactions"("created_at");
