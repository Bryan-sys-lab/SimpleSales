-- Reconciles a database that already existed on the Supabase-era schema with
-- the Prisma schema, and folds in what `prisma/ROLE_MIGRATION.sql` used to do.
--
-- Why this exists
-- ---------------
-- The shops already running in production were created by
-- `supabase/migrations/0001_schema.sql`, which named the role enum `user_role`
-- with the values ('owner','staff'). `ROLE_MIGRATION.sql` assumed a type named
-- `"UserRole"`, so its very first statement failed on exactly the database it
-- was written for, and because it sat outside `prisma/migrations/` Prisma never
-- ran it either. The result was an existing shop that could never be brought
-- up to the Prisma schema, and a `requireOwner` check that could never pass
-- because Express writes 'admin'/'cashier' while the column still said
-- 'owner'/'staff'.
--
-- Everything below is guarded and re-runnable, so the same script is safe on a
-- fresh database (where `init` already created the canonical shape and every
-- step becomes a no-op) and on a legacy one.

-- ---------------------------------------------------------------------------
-- 1. Columns that the legacy tables do not have.
--
--    `init` uses CREATE TABLE IF NOT EXISTS, so on a database that already has
--    these tables the whole definition is skipped — including the columns
--    added since. Each one is added explicitly here.
-- ---------------------------------------------------------------------------
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "oidc_subject" TEXT;
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "local_id" INTEGER;
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "email" TEXT;
ALTER TABLE "profiles" ADD COLUMN IF NOT EXISTS "deleted_at" TIMESTAMP(3);
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "category" TEXT NOT NULL DEFAULT 'General';
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "excise_stamp_batch" TEXT;
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "active" BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "bottle_ml" INTEGER NOT NULL DEFAULT 750;
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "half_price" DECIMAL(12,2);
ALTER TABLE "products" ADD COLUMN IF NOT EXISTS "quarter_price" DECIMAL(12,2);
ALTER TABLE "sales" ADD COLUMN IF NOT EXISTS "payment_reference" TEXT;
ALTER TABLE "sale_items" ADD COLUMN IF NOT EXISTS "portion" TEXT NOT NULL DEFAULT 'full';
ALTER TABLE "sale_items" ADD COLUMN IF NOT EXISTS "portion_ml" INTEGER NOT NULL DEFAULT 0;
ALTER TABLE "payments" ADD COLUMN IF NOT EXISTS "checkout_request_id" TEXT;
ALTER TABLE "payments" ADD COLUMN IF NOT EXISTS "sale_id" TEXT;

-- Tables the legacy schema never had. The audit trail for cashier deletion
-- lives in deletion_ledger, and `/api/tenant/staff/:id` writes to it, so
-- without this every delete request would fail.
CREATE TABLE IF NOT EXISTS "deletion_ledger" (
  "id" TEXT NOT NULL,
  "tenant_id" TEXT NOT NULL,
  "subject_type" TEXT NOT NULL,
  "subject_id" TEXT NOT NULL,
  "reason" TEXT,
  "status" TEXT NOT NULL DEFAULT 'COMPLETED',
  "requested_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
  "completed_at" TIMESTAMP(3),
  CONSTRAINT "deletion_ledger_pkey" PRIMARY KEY ("id")
);

-- ---------------------------------------------------------------------------
-- 2. Portion math needs fractional stock and quantity; the legacy schema used
--    integers, so a half bottle could not be represented at all.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'products' AND column_name = 'stock_qty'
      AND data_type = 'integer'
  ) THEN
    ALTER TABLE "products" ALTER COLUMN "stock_qty" TYPE DECIMAL(12,3) USING "stock_qty"::DECIMAL;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'sale_items' AND column_name = 'qty'
      AND data_type = 'integer'
  ) THEN
    ALTER TABLE "sale_items" ALTER COLUMN "qty" TYPE DECIMAL(12,3) USING "qty"::DECIMAL;
  END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- 3. Role vocabulary: ('owner','staff') -> ('admin','manager','cashier').
--
--    Whichever enum the column currently uses is discovered from the catalog
--    rather than assumed, so this works whether the database came from the
--    Supabase schema (`user_role`) or from a Prisma baseline (`UserRole`).
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  role_type text;
BEGIN
  SELECT t.typname INTO role_type
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  JOIN pg_type t ON t.oid = a.atttypid
  WHERE c.relname = 'profiles'
    AND a.attname = 'role'
    AND NOT a.attisdropped;

  IF role_type IS NULL THEN
    RAISE NOTICE 'profiles.role not found; skipping role migration';
    RETURN;
  END IF;

  IF role_type = 'UserRole' THEN
    RAISE NOTICE 'profiles.role already uses the canonical UserRole type';
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserRole') THEN
    CREATE TYPE "UserRole" AS ENUM ('admin', 'manager', 'cashier');
  END IF;

  -- The column default references the old type, so it has to go first.
  IF EXISTS (
    SELECT 1 FROM pg_attrdef d
    JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE a.attrelid = 'profiles'::regclass AND a.attname = 'role'
  ) THEN
    ALTER TABLE "profiles" ALTER COLUMN "role" DROP DEFAULT;
  END IF;

  -- owner -> admin, staff -> cashier, anything unexpected -> cashier. The
  -- fallback is the least-privileged value, so an unmapped legacy row can
  -- never gain access.
  EXECUTE format(
    'ALTER TABLE "profiles" ALTER COLUMN "role" TYPE "UserRole" USING ('
    '  CASE %I::text'
    '    WHEN ''owner'' THEN ''admin'''
    '    WHEN ''staff'' THEN ''cashier'''
    '    WHEN ''manager'' THEN ''manager'''
    '    WHEN ''admin'' THEN ''admin'''
    '    WHEN ''cashier'' THEN ''cashier'''
    '    ELSE ''cashier'''
    '  END)::"UserRole"',
    role_type);

  ALTER TABLE "profiles" ALTER COLUMN "role" SET DEFAULT 'cashier'::"UserRole";

  EXECUTE format('DROP TYPE IF EXISTS %I', role_type);
END
$$;

-- ---------------------------------------------------------------------------
-- 4. Indexes and constraints the legacy schema lacks.
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS "profiles_tenant_id_idx" ON "profiles"("tenant_id");
CREATE INDEX IF NOT EXISTS "profiles_oidc_subject_idx" ON "profiles"("oidc_subject");
CREATE INDEX IF NOT EXISTS "products_tenant_id_idx" ON "products"("tenant_id");
CREATE INDEX IF NOT EXISTS "sales_tenant_id_created_at_idx" ON "sales"("tenant_id", "created_at");
CREATE INDEX IF NOT EXISTS "sale_items_sale_id_idx" ON "sale_items"("sale_id");
CREATE INDEX IF NOT EXISTS "stock_adjustments_tenant_id_idx" ON "stock_adjustments"("tenant_id");
CREATE INDEX IF NOT EXISTS "payments_tenant_id_idx" ON "payments"("tenant_id");
CREATE INDEX IF NOT EXISTS "payments_reference_idx" ON "payments"("reference");
CREATE INDEX IF NOT EXISTS "deletion_ledger_tenant_id_subject_type_subject_id_idx"
  ON "deletion_ledger"("tenant_id", "subject_type", "subject_id");

-- `local_id` is nullable, so a partial unique index is what actually prevents
-- two cashiers in one shop from claiming the same till-local id.
CREATE UNIQUE INDEX IF NOT EXISTS "profiles_tenant_id_local_id_key"
  ON "profiles"("tenant_id", "local_id") WHERE "local_id" IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS "payments_reference_key" ON "payments"("reference");
CREATE UNIQUE INDEX IF NOT EXISTS "payments_sale_id_key"
  ON "payments"("sale_id") WHERE "sale_id" IS NOT NULL;

DO $$
DECLARE
  fk record;
BEGIN
  FOR fk IN
    SELECT * FROM (VALUES
      ('profiles_tenant_id_fkey',             'profiles',           'tenant_id',   'tenants',  'CASCADE'),
      ('products_tenant_id_fkey',             'products',           'tenant_id',   'tenants',  'CASCADE'),
      ('sales_tenant_id_fkey',                'sales',              'tenant_id',   'tenants',  'CASCADE'),
      ('sale_items_tenant_id_fkey',           'sale_items',         'tenant_id',   'tenants',  'CASCADE'),
      ('sale_items_sale_id_fkey',             'sale_items',         'sale_id',     'sales',    'CASCADE'),
      ('sale_items_product_id_fkey',          'sale_items',         'product_id',  'products', 'RESTRICT'),
      ('stock_adjustments_tenant_id_fkey',    'stock_adjustments',  'tenant_id',   'tenants',  'CASCADE'),
      ('payments_tenant_id_fkey',             'payments',           'tenant_id',   'tenants',  'CASCADE'),
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
