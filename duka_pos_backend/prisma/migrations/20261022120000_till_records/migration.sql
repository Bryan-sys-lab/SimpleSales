-- The till's records: shifts, returns, purchases and shot cups, plus the
-- local id that makes a push from a phone idempotent.
--
-- Every table here is written by a TILL, offline, and pushed to the server
-- when the phone can reach it. The `local_id` column is what makes that push
-- idempotent: the same sale arriving twice is one sale.
--
-- Every statement is guarded, so the migration can be applied to a database
-- that already carries some of these objects.

-- The till's own id for a sale, unique within a shop.
ALTER TABLE "sales" ADD COLUMN IF NOT EXISTS "local_id" INTEGER;
CREATE UNIQUE INDEX IF NOT EXISTS "sales_tenant_id_local_id_key" ON "sales"("tenant_id", "local_id");

-- A sale may name a person the server has not heard of yet, and a line may
-- name a product the catalogue has not caught up with. The NAME is on the row
-- either way.
ALTER TABLE "sales" ALTER COLUMN "staff_id" DROP NOT NULL;
ALTER TABLE "sale_items" ALTER COLUMN "product_id" DROP NOT NULL;

-- A shift: a drawer, and the people who worked it.
CREATE TABLE IF NOT EXISTS "shifts" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER NOT NULL,
    "staff_id" TEXT,
    "staff_name" TEXT NOT NULL,
    "start_time" TIMESTAMP(3) NOT NULL,
    "end_time" TIMESTAMP(3),
    "start_float" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "end_float" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "expected_cash" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "counted_cash" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'open',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "shifts_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "shifts_tenant_id_local_id_key" ON "shifts"("tenant_id", "local_id");
CREATE INDEX IF NOT EXISTS "shifts_tenant_id_start_time_idx" ON "shifts"("tenant_id", "start_time");

-- A return: money and stock going back to the shop.
CREATE TABLE IF NOT EXISTS "returns" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER NOT NULL,
    "original_sale_local_id" INTEGER,
    "kind" TEXT NOT NULL DEFAULT 'refund',
    "reason" TEXT NOT NULL,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "profit" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "staff_id" TEXT,
    "staff_name" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "returns_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "returns_tenant_id_local_id_key" ON "returns"("tenant_id", "local_id");
CREATE INDEX IF NOT EXISTS "returns_tenant_id_created_at_idx" ON "returns"("tenant_id", "created_at");

-- One line of a return.
CREATE TABLE IF NOT EXISTS "return_items" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "return_id" TEXT NOT NULL,
    "product_id" TEXT,
    "product_name" TEXT NOT NULL,
    "qty" DECIMAL(12,3) NOT NULL,
    "unit_price" DECIMAL(12,2) NOT NULL,
    "unit_cost" DECIMAL(12,2) NOT NULL,
    "portion" TEXT NOT NULL DEFAULT 'full',
    "portion_ml" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "return_items_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "return_items_return_id_idx" ON "return_items"("return_id");

-- A purchase: stock arriving at the shop, and what it cost.
CREATE TABLE IF NOT EXISTS "purchases" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER NOT NULL,
    "supplier_name" TEXT NOT NULL,
    "invoice_number" TEXT,
    "total" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "staff_id" TEXT,
    "staff_name" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "purchases_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "purchases_tenant_id_local_id_key" ON "purchases"("tenant_id", "local_id");
CREATE INDEX IF NOT EXISTS "purchases_tenant_id_created_at_idx" ON "purchases"("tenant_id", "created_at");

-- One line of a purchase.
CREATE TABLE IF NOT EXISTS "purchase_items" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "purchase_id" TEXT NOT NULL,
    "product_id" TEXT,
    "product_name" TEXT NOT NULL,
    "qty" DECIMAL(12,3) NOT NULL,
    "unit_cost" DECIMAL(12,2) NOT NULL,
    CONSTRAINT "purchase_items_pkey" PRIMARY KEY ("id")
);
CREATE INDEX IF NOT EXISTS "purchase_items_purchase_id_idx" ON "purchase_items"("purchase_id");

-- A shot cup: a named serving poured from a drink. The size is optional, and
-- zero means "not known".
CREATE TABLE IF NOT EXISTS "shot_cups" (
    "id" TEXT NOT NULL,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER NOT NULL,
    "product_id" TEXT NOT NULL,
    "product_name" TEXT NOT NULL,
    "label" TEXT NOT NULL,
    "capacity_ml" INTEGER NOT NULL DEFAULT 0,
    "price" DECIMAL(12,2) NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "shot_cups_pkey" PRIMARY KEY ("id")
);
CREATE UNIQUE INDEX IF NOT EXISTS "shot_cups_tenant_id_local_id_key" ON "shot_cups"("tenant_id", "local_id");
CREATE INDEX IF NOT EXISTS "shot_cups_tenant_id_product_id_idx" ON "shot_cups"("tenant_id", "product_id");
