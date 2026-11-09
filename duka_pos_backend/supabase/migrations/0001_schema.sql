-- Duka POS — multi-tenant schema
-- Every business table carries tenant_id and is isolated by Row Level
-- Security (see 0002_rls.sql) rather than by application code remembering
-- to filter — that's the actual point of RLS: even a bug in the Flutter
-- app, or someone hitting the API directly with a stolen token, cannot
-- read or write another shop's rows, because the database itself refuses.

create extension if not exists "uuid-ossp";

-- One row per shop. This is the "tenant."
create table tenants (
  id uuid primary key default uuid_generate_v4(),
  shop_name text not null,
  created_at timestamptz not null default now(),
  -- Feature toggles the owner controls from Settings (Included/Excluded).
  mpesa_enabled boolean not null default false,
  etims_enabled boolean not null default false,
  -- PayHero merchant config, entered once by the owner when they enable
  -- M-Pesa — found on the shop's own PayHero dashboard. Nothing secret is
  -- stored here: the actual API credentials live only in Supabase's Edge
  -- Function secrets (see functions/_shared/payhero.ts), never in a table
  -- any client can read.
  payhero_channel_id integer,
  payhero_credential_id text
);

-- One row per human who can sign in, linked to Supabase's built-in auth.users.
-- Role lives here, not just client-side, because RLS policies read it —
-- a staff account can never grant itself owner privileges by editing local
-- app state, since the database checks this table on every request.
--
-- This is the vocabulary the Express API and the Prisma schema both use. The
-- older ('owner','staff') values are remapped by
-- prisma/migrations/20260929220000_reconcile_legacy_roles, and `is_owner()` in
-- 0002_rls.sql still accepts both so a database mid-migration keeps working.
create type user_role as enum ('admin', 'manager', 'cashier');

create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references tenants(id) on delete cascade,
  -- The OIDC subject this till belongs to. `auth.users.id` is the Supabase
  -- account, which is a different identity from the shop's Keycloak login, so
  -- the online linkage is recorded separately.
  oidc_subject text,
  -- Stable id the till uses locally, so a cashier record survives a reinstall.
  local_id integer,
  email text,
  name text not null,
  role user_role not null default 'cashier',
  active boolean not null default true,
  -- Set when a cashier is removed. The row is retained as a tombstone so the
  -- financial ledger keeps its foreign keys, while the personal name is
  -- replaced.
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  constraint profiles_tenant_id_local_id_key unique (tenant_id, local_id)
);

create index profiles_oidc_subject_idx on profiles(oidc_subject);

-- Audit trail for identity removal. Written by the cashier-deletion endpoint
-- before the profile is anonymised, so a request that half-completes is still
-- attributable.
create table deletion_ledger (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  subject_type text not null,
  subject_id uuid not null,
  reason text,
  status text not null default 'COMPLETED',
  requested_at timestamptz not null default now(),
  completed_at timestamptz
);

create index deletion_ledger_lookup_idx
  on deletion_ledger(tenant_id, subject_type, subject_id);

create table products (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  name text not null,
  category text not null default 'General',
  cost_price numeric(12,2) not null check (cost_price >= 0),
  sell_price numeric(12,2) not null check (sell_price >= 0),
  -- Fractional: a bottle is divisible into halves and quarters, and stock is
  -- tracked in bottle units, so an integer column silently lost every partial
  -- serving and made `stock_units` comparisons four times too lenient.
  stock_qty numeric(12,3) not null default 0 check (stock_qty >= 0),
  reorder_level integer not null default 5 check (reorder_level >= 0),
  bottle_ml integer not null default 750 check (bottle_ml between 1 and 10000),
  -- Per-serving prices. The Express route falls back to sellPrice/2 and
  -- sellPrice/4 when these are null, so they are optional by design.
  half_price numeric(12,2) check (half_price >= 0),
  quarter_price numeric(12,2) check (quarter_price >= 0),
  excise_stamp_batch text,
  active boolean not null default true,
  updated_at timestamptz not null default now()
);

create table sales (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  staff_id uuid not null references profiles(id), -- the Supabase account the device is registered under (see design note below)
  staff_name text not null, -- the actual cashier, from the local PIN session — see design note
  payment_method text not null default 'cash' check (payment_method in ('cash', 'mpesa')),
  payment_reference text, -- PayHero transaction reference, for mpesa sales
  total numeric(12,2) not null,
  profit numeric(12,2) not null,
  created_at timestamptz not null default now()
);

create table sale_items (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  sale_id uuid not null references sales(id) on delete cascade,
  product_id uuid not null references products(id),
  product_name text not null, -- snapshot, so renaming/deleting a product later doesn't rewrite history
  qty numeric(12,3) not null check (qty > 0),
  unit_price numeric(12,2) not null,
  unit_cost numeric(12,2) not null,
  portion text not null default 'full' check (portion in ('full','half','quarter')),
  portion_ml integer not null default 0
);

create table stock_adjustments (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  product_id uuid not null references products(id),
  product_name text not null,
  delta integer not null,
  reason text,
  staff_id uuid not null references profiles(id),
  created_at timestamptz not null default now()
);

-- M-Pesa (PayHero) transactions. Deliberately a separate table from `sales`:
-- a payment can be QUEUED or FAILED without a sale ever existing, and the
-- sale itself is only created once payment is confirmed SUCCESS (see the
-- payhero-callback Edge Function) — this prevents stock being decremented
-- for a payment that never actually completed.
-- Design note on `initiated_by` vs `staff_name`: staff sign in locally via
-- PIN only (see the Flutter app's existing login screen) and do not each
-- get their own Supabase account — that would mean provisioning a cloud
-- identity per till worker, which is real added complexity for uncertain
-- benefit at this stage. Instead, one Supabase session per *device* is
-- created when the owner first enables M-Pesa (registering that till with
-- the backend), and every M-Pesa payment from that till authenticates as
-- that device/owner session while carrying the actual cashier's name as
-- plain text in `staff_name` for reporting. This means backend-side RLS
-- and audit trails are enforced at the till/tenant level, not the
-- individual-staff level, for the M-Pesa path specifically — cash sales
-- keep their existing, stronger per-staff local attribution untouched.
-- Revisit if per-staff backend accounts become worth the added setup cost.
create table payments (
  id uuid primary key default uuid_generate_v4(),
  tenant_id uuid not null references tenants(id) on delete cascade,
  initiated_by uuid not null references profiles(id),
  staff_name text not null,
  reference text not null unique, -- our external_reference, also used to query PayHero
  checkout_request_id text,
  phone_number text not null,
  amount numeric(12,2) not null,
  -- PENDING is the "STK push sent, awaiting the customer" state. Both payment
  -- paths set it the moment the push succeeds, and the callback and status
  -- endpoints branch on it, so a vocabulary without it made every successful
  -- push fail its own CHECK constraint.
  status text not null default 'QUEUED' check (status in ('QUEUED', 'PENDING', 'SUCCESS', 'FAILED')),
  cart_snapshot jsonb not null, -- the items being paid for, so the callback can build the sale after confirmation
  sale_id uuid references sales(id), -- set once the sale is created on SUCCESS
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_products_tenant on products(tenant_id);
create index idx_sales_tenant_date on sales(tenant_id, created_at);
create index idx_sale_items_sale on sale_items(sale_id);
create index idx_stock_adj_tenant on stock_adjustments(tenant_id);
create index idx_payments_tenant on payments(tenant_id);
create index idx_payments_reference on payments(reference);
