-- Baseline schema for the Express + Prisma backend.
--
-- Every statement is guarded so this migration can be applied to a database
-- that already carries these objects. The shops already running on the
-- Supabase-era schema have the same table names, and an unguarded CREATE
-- aborted the whole chain on `relation "tenants" already exists` — which
-- left `prisma migrate deploy` permanently unable to advance.
--
-- Note PostgreSQL has no `CREATE TYPE IF NOT EXISTS`, so the enum is created
-- inside a DO block. Where an existing table's shape differs (uuid ids, integer
-- stock, the older role vocabulary) the additive reconciliation lives in the
-- later migrations rather than here, so re-running this file is always safe.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserRole') THEN
    CREATE TYPE "UserRole" AS ENUM ('admin', 'manager', 'cashier');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS "tenants" ("id" TEXT NOT NULL, "shop_name" TEXT NOT NULL, "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "mpesa_enabled" BOOLEAN NOT NULL DEFAULT false, "etims_enabled" BOOLEAN NOT NULL DEFAULT false, "payhero_channel_id" INTEGER, "payhero_credential_id" TEXT, CONSTRAINT "tenants_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "profiles" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "oidc_subject" TEXT, "local_id" INTEGER, "email" TEXT, "name" TEXT NOT NULL, "role" "UserRole" NOT NULL DEFAULT 'cashier', "active" BOOLEAN NOT NULL DEFAULT true, "deleted_at" TIMESTAMP(3), "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "profiles_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "products" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "name" TEXT NOT NULL, "category" TEXT NOT NULL DEFAULT 'General', "cost_price" DECIMAL(12,2) NOT NULL, "sell_price" DECIMAL(12,2) NOT NULL, "stock_qty" DECIMAL(12,3) NOT NULL DEFAULT 0, "reorder_level" INTEGER NOT NULL DEFAULT 5, "bottle_ml" INTEGER NOT NULL DEFAULT 750, "half_price" DECIMAL(12,2), "quarter_price" DECIMAL(12,2), "excise_stamp_batch" TEXT, "active" BOOLEAN NOT NULL DEFAULT true, "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "products_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "sales" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "staff_id" TEXT NOT NULL, "staff_name" TEXT NOT NULL, "payment_method" TEXT NOT NULL DEFAULT 'cash', "payment_reference" TEXT, "total" DECIMAL(12,2) NOT NULL, "profit" DECIMAL(12,2) NOT NULL, "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "sales_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "sale_items" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "sale_id" TEXT NOT NULL, "product_id" TEXT NOT NULL, "product_name" TEXT NOT NULL, "qty" DECIMAL(12,3) NOT NULL, "unit_price" DECIMAL(12,2) NOT NULL, "unit_cost" DECIMAL(12,2) NOT NULL, "portion" TEXT NOT NULL DEFAULT 'full', "portion_ml" INTEGER NOT NULL DEFAULT 0, CONSTRAINT "sale_items_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "stock_adjustments" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "product_id" TEXT NOT NULL, "product_name" TEXT NOT NULL, "delta" INTEGER NOT NULL, "reason" TEXT, "staff_id" TEXT NOT NULL, "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "stock_adjustments_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "payments" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "initiated_by" TEXT NOT NULL, "staff_name" TEXT NOT NULL, "reference" TEXT NOT NULL, "checkout_request_id" TEXT, "phone_number" TEXT NOT NULL, "amount" DECIMAL(12,2) NOT NULL, "status" TEXT NOT NULL DEFAULT 'QUEUED', "cart_snapshot" JSONB NOT NULL, "sale_id" TEXT, "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT "payments_pkey" PRIMARY KEY ("id"));
CREATE TABLE IF NOT EXISTS "deletion_ledger" ("id" TEXT NOT NULL, "tenant_id" TEXT NOT NULL, "subject_type" TEXT NOT NULL, "subject_id" TEXT NOT NULL, "reason" TEXT, "status" TEXT NOT NULL DEFAULT 'COMPLETED', "requested_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP, "completed_at" TIMESTAMP(3), CONSTRAINT "deletion_ledger_pkey" PRIMARY KEY ("id"));

CREATE INDEX IF NOT EXISTS "profiles_tenant_id_idx" ON "profiles"("tenant_id");
CREATE INDEX IF NOT EXISTS "profiles_oidc_subject_idx" ON "profiles"("oidc_subject");
CREATE UNIQUE INDEX IF NOT EXISTS "profiles_tenant_id_local_id_key" ON "profiles"("tenant_id", "local_id");
CREATE INDEX IF NOT EXISTS "products_tenant_id_idx" ON "products"("tenant_id");
CREATE INDEX IF NOT EXISTS "sales_tenant_id_created_at_idx" ON "sales"("tenant_id", "created_at");
CREATE INDEX IF NOT EXISTS "sale_items_sale_id_idx" ON "sale_items"("sale_id");
CREATE INDEX IF NOT EXISTS "stock_adjustments_tenant_id_idx" ON "stock_adjustments"("tenant_id");
CREATE UNIQUE INDEX IF NOT EXISTS "payments_reference_key" ON "payments"("reference");
CREATE UNIQUE INDEX IF NOT EXISTS "payments_sale_id_key" ON "payments"("sale_id");
CREATE INDEX IF NOT EXISTS "payments_tenant_id_idx" ON "payments"("tenant_id");
CREATE INDEX IF NOT EXISTS "payments_reference_idx" ON "payments"("reference");
CREATE INDEX IF NOT EXISTS "deletion_ledger_tenant_id_subject_type_subject_id_idx" ON "deletion_ledger"("tenant_id", "subject_type", "subject_id");

-- Foreign keys are added through a guard, because `ALTER TABLE ... ADD
-- CONSTRAINT` has no IF NOT EXISTS form and re-running it aborts the whole
-- transaction. The table below is the single source of truth for which
-- columns reference which parent.
DO $$
DECLARE
  fk record;
BEGIN
  FOR fk IN
    SELECT * FROM (VALUES
      ('profiles_tenant_id_fkey',             'profiles',           'tenant_id',   'tenants',  'CASCADE'),
      ('products_tenant_id_fkey',             'products',           'tenant_id',   'tenants',  'CASCADE'),
      ('sales_tenant_id_fkey',                'sales',              'tenant_id',   'tenants',  'CASCADE'),
      ('sales_staff_id_fkey',                 'sales',              'staff_id',    'profiles', 'RESTRICT'),
      ('sale_items_tenant_id_fkey',           'sale_items',         'tenant_id',   'tenants',  'CASCADE'),
      ('sale_items_sale_id_fkey',             'sale_items',         'sale_id',     'sales',    'CASCADE'),
      ('sale_items_product_id_fkey',          'sale_items',         'product_id',  'products', 'RESTRICT'),
      ('stock_adjustments_tenant_id_fkey',    'stock_adjustments',  'tenant_id',   'tenants',  'CASCADE'),
      ('stock_adjustments_product_id_fkey',   'stock_adjustments',  'product_id',  'products', 'RESTRICT'),
      ('stock_adjustments_staff_id_fkey',     'stock_adjustments',  'staff_id',    'profiles', 'RESTRICT'),
      ('payments_tenant_id_fkey',             'payments',           'tenant_id',   'tenants',  'CASCADE'),
      ('payments_initiated_by_fkey',          'payments',           'initiated_by','profiles', 'RESTRICT'),
      ('payments_sale_id_fkey',               'payments',           'sale_id',     'sales',    'SET NULL'),
      ('deletion_ledger_tenant_id_fkey',      'deletion_ledger',    'tenant_id',   'tenants',  'CASCADE')
    ) AS t(constraint_name, table_name, column_name, parent_table, on_delete)
  LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = fk.constraint_name) THEN
      EXECUTE format(
        'ALTER TABLE %I ADD CONSTRAINT %I FOREIGN KEY (%I) REFERENCES %I("id") ON DELETE %s ON UPDATE CASCADE',
        fk.table_name, fk.constraint_name, fk.column_name, fk.parent_table, fk.on_delete);
    END IF;
  END LOOP;
END
$$;
