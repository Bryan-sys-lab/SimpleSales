-- ============================================================================
-- Retained for operators who were told to run this by hand.
--
-- The real work now lives in the Prisma migration chain, specifically
-- `prisma/migrations/20260929220000_reconcile_legacy_roles/migration.sql`,
-- which replaces owner/staff with admin/manager/cashier AND adds every column,
-- table and index the legacy Supabase-era schema is missing.
--
-- It used to be safe to run this instead of the migrations. It was not, for two
-- reasons:
--   * it renamed a type named "UserRole", but the Supabase-era schema created
--     the type as `user_role`, so the first statement failed on exactly the
--     database this script was written for; and
--   * it never added `deletion_ledger`, the `profiles` OIDC columns, or the
--     portion/decimal-stock columns, so a shop left half-migrated could not
--     serve requests.
--
-- PREFER `npm run db:deploy` (prisma migrate deploy), which applies the whole
-- ordered chain and is re-runnable. This file is kept working so an operator
-- who has it in a runbook is not left with a broken command.
-- ============================================================================

\echo 'Applying role reconciliation (see prisma/migrations/20260929220000_reconcile_legacy_roles)...'

DO $$
DECLARE
  role_type text;
BEGIN
  SELECT t.typname INTO role_type
  FROM pg_attribute a
  JOIN pg_class c ON c.oid = a.attrelid
  JOIN pg_type t ON t.oid = a.atttypid
  WHERE c.relname = 'profiles'
    AND a.attname = 'role'
    AND NOT a.attisdropped;

  IF role_type IS NULL OR role_type = 'UserRole' THEN
    RAISE NOTICE 'profiles.role already uses the canonical UserRole type; nothing to do';
    RETURN;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'UserRole') THEN
    CREATE TYPE "UserRole" AS ENUM ('admin', 'manager', 'cashier');
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_attrdef d
    JOIN pg_attribute a ON a.attrelid = d.adrelid AND a.attnum = d.adnum
    WHERE a.attrelid = 'profiles'::regclass AND a.attname = 'role'
  ) THEN
    ALTER TABLE "profiles" ALTER COLUMN "role" DROP DEFAULT;
  END IF;

  EXECUTE format(
    'ALTER TABLE "profiles" ALTER COLUMN "role" TYPE "UserRole" USING ('
    '  CASE %I::text'
    "    WHEN 'owner' THEN 'admin'"
    "    WHEN 'staff' THEN 'cashier'"
    "    WHEN 'manager' THEN 'manager'"
    "    WHEN 'admin' THEN 'admin'"
    "    WHEN 'cashier' THEN 'cashier'"
    "    ELSE 'cashier'"
    '  END)::"UserRole"',
    role_type);

  ALTER TABLE "profiles" ALTER COLUMN "role" SET DEFAULT 'cashier'::"UserRole";

  EXECUTE format('DROP TYPE IF EXISTS %I', role_type);
END
$$;

\echo 'Role vocabulary reconciled. Run `npm run db:deploy` to apply the remaining schema changes.'
