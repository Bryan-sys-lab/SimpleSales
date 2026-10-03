-- ============================================================================
-- OPTIONAL defence-in-depth: PostgreSQL row-level security for tenant tables.
-- ============================================================================
--
-- DO NOT RUN THIS WITH `prisma migrate deploy`. It is intentionally kept out
-- of prisma/migrations/ because the API does not yet set a per-transaction
-- tenant context. Applying it today would make every tenant-scoped query
-- return zero rows and would break the cross-tenant system-admin endpoints.
--
-- The application already enforces isolation in code: the `x-tenant-id`
-- header is checked against the caller's OIDC profile memberships on every
-- protected request, and every query is filtered by that tenant.
--
-- To enable RLS safely you must FIRST:
--
--   1. Connect using a dedicated NON-SUPERUSER role. Superusers bypass RLS,
--      so policies would have no effect (false sense of security).
--
--   2. Wrap every tenant-scoped unit of work in a single interactive
--      transaction that sets the tenant context first, e.g.:
--
--        await prisma.$transaction(async (tx) => {
--          await tx.$executeRaw`SELECT set_config('app.tenant_id', ${tenantId}, true)`;
--          return tx.product.findMany({ where: { tenantId } });
--        });
--
--      The third argument `true` makes the setting transaction-local, so a
--      pooled connection can never leak one tenant's context into another
--      tenant's request.
--
--   3. Give the platform system-admin endpoints their own path that either
--      runs under a dedicated BYPASSRLS role, or a separate policy that
--      permits cross-tenant reads only for a dedicated database role. Never
--      simply omit the tenant context for those routes.
--
-- After steps 1-3 are implemented and tested, apply this file manually:
--   psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f prisma/ENABLE_RLS.sql
--
-- Rollback: drop the policies and disable RLS on the same tables.
-- ============================================================================

DO $$
DECLARE
  table_name text;
BEGIN
  FOREACH table_name IN ARRAY ARRAY['profiles','products','sales','sale_items','stock_adjustments','payments','deletion_ledger']
  LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', table_name);
    EXECUTE format('ALTER TABLE %I FORCE ROW LEVEL SECURITY', table_name);
    EXECUTE format('DROP POLICY IF EXISTS tenant_isolation ON %I', table_name);
    EXECUTE format(
      'CREATE POLICY tenant_isolation ON %I USING (tenant_id::text = current_setting(''app.tenant_id'', true)) WITH CHECK (tenant_id::text = current_setting(''app.tenant_id'', true))',
      table_name);
  END LOOP;
END $$;
