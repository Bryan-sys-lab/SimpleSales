-- Row Level Security: tenant isolation + role-based access control
--
-- Two helper functions read the signed-in user's own profile row to answer
-- "which tenant is this person in?" and "are they the owner?" — every
-- policy below is built from just these two, so the isolation logic lives
-- in exactly one place rather than being re-derived per table.
--
-- security definer + a fixed search_path is required here: these functions
-- must read `profiles` regardless of the calling user's own RLS visibility
-- into that table, or every policy that depends on them would deadlock
-- against itself.

create or replace function current_tenant_id()
returns uuid
language sql security definer set search_path = public stable
as $$
  select tenant_id from profiles where id = auth.uid();
$$;

create or replace function is_owner()
returns boolean
language sql security definer set search_path = public stable
as $$
  -- Matches both role vocabularies. The enum was remapped from
  -- ('owner','staff') to ('admin','manager','cashier') — the same vocabulary
  -- the Express API writes and the Prisma schema declares — so keying this on
  -- 'owner' alone silently stopped every owner-only policy from ever being
  -- true once a shop had been migrated.
  select role::text in ('owner', 'admin') from profiles where id = auth.uid();
$$;

alter table tenants enable row level security;
alter table profiles enable row level security;
alter table products enable row level security;
alter table sales enable row level security;
alter table sale_items enable row level security;
alter table stock_adjustments enable row level security;
alter table payments enable row level security;

-- ---------------- tenants ----------------
-- Everyone in the tenant can read their own shop's settings; only the
-- owner can change them (e.g. flipping mpesa_enabled / etims_enabled).
create policy tenant_select on tenants for select
  using (id = current_tenant_id());
create policy tenant_update_owner on tenants for update
  using (id = current_tenant_id() and is_owner());

-- ---------------- profiles ----------------
-- Everyone can see their teammates within the same tenant (needed for the
-- login picker and sales-by-staff reports) but never another tenant's staff.
create policy profiles_select_same_tenant on profiles for select
  using (tenant_id = current_tenant_id());
-- Only the owner can add/deactivate/edit staff. Note this also blocks a
-- staff account from promoting itself to owner — role is not client-editable.
create policy profiles_insert_owner on profiles for insert
  with check (tenant_id = current_tenant_id() and is_owner());
create policy profiles_update_owner on profiles for update
  using (tenant_id = current_tenant_id() and is_owner());

-- ---------------- products ----------------
create policy products_select on products for select
  using (tenant_id = current_tenant_id());
create policy products_insert on products for insert
  with check (tenant_id = current_tenant_id());
create policy products_update on products for update
  using (tenant_id = current_tenant_id());
-- Deactivating (soft-delete) a product is owner-only, matching the app's
-- existing owner-only "Delete" button.
create policy products_delete_owner on products for update
  using (tenant_id = current_tenant_id() and is_owner());

-- ---------------- sales & sale_items ----------------
-- Both staff and owner can create sales (that's the whole point of the
-- Sell screen). Nobody can UPDATE or DELETE a sale once written — there is
-- deliberately no update/delete policy on `sales` below, which means the
-- database itself refuses edits to sales history, full stop. Corrections
-- happen via a new stock_adjustment or a documented manual process, never
-- by silently rewriting what was actually sold.
create policy sales_select on sales for select
  using (tenant_id = current_tenant_id());
create policy sales_insert on sales for insert
  with check (tenant_id = current_tenant_id());

create policy sale_items_select on sale_items for select
  using (tenant_id = current_tenant_id());
create policy sale_items_insert on sale_items for insert
  with check (tenant_id = current_tenant_id());

-- ---------------- stock_adjustments ----------------
-- Both roles can log a restock/breakage (matches the app's existing
-- "Adjust stock" button, available to staff), but — like sales — these are
-- append-only. No update/delete policy exists, so the log can't be edited
-- after the fact, which is the entire point of it being an audit trail.
create policy stock_adj_select on stock_adjustments for select
  using (tenant_id = current_tenant_id());
create policy stock_adj_insert on stock_adjustments for insert
  with check (tenant_id = current_tenant_id());

-- ---------------- payments ----------------
-- Payments are only ever written by the Edge Functions (using the Supabase
-- service role, which bypasses RLS by design — see the functions'
-- comments), never directly by the app with the user's own token. Staff and
-- owner can both read payment status for their own tenant, which is what
-- lets the Sell screen poll/observe a payment's progress.
create policy payments_select on payments for select
  using (tenant_id = current_tenant_id());
