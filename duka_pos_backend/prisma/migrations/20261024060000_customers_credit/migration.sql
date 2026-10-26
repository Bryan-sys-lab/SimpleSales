CREATE TABLE "customers" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_uuid" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "tin" TEXT,
    "notes" TEXT,
    "credit_limit_minor" INTEGER,
    "balance_minor" INTEGER NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "customers_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "customers_tenant_id_local_uuid_key" ON "customers"("tenant_id", "local_uuid");
CREATE INDEX "customers_tenant_id_name_idx" ON "customers"("tenant_id", "name");
ALTER TABLE "customers" ADD CONSTRAINT "customers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;

CREATE TABLE "credit_ledger" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_uuid" TEXT NOT NULL,
    "customer_id" TEXT NOT NULL,
    "entry_type" TEXT NOT NULL,
    "amount_minor" INTEGER NOT NULL,
    "sale_local_id" INTEGER,
    "return_local_id" INTEGER,
    "payment_method" TEXT,
    "reference" TEXT,
    "staff_name" TEXT NOT NULL,
    "note" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL,
    CONSTRAINT "credit_ledger_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX "credit_ledger_tenant_id_local_uuid_key" ON "credit_ledger"("tenant_id", "local_uuid");
CREATE INDEX "credit_ledger_tenant_id_customer_id_created_at_idx" ON "credit_ledger"("tenant_id", "customer_id", "created_at");
ALTER TABLE "credit_ledger" ADD CONSTRAINT "credit_ledger_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "credit_ledger" ADD CONSTRAINT "credit_ledger_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "customers"("id") ON DELETE CASCADE ON UPDATE CASCADE;
