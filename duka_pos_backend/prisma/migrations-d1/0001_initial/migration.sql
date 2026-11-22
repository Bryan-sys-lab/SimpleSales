-- CreateTable
CREATE TABLE "tenants" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "shop_name" TEXT NOT NULL,
    "business_profile" TEXT NOT NULL DEFAULT 'duka',
    "mpesa_enabled" BOOLEAN NOT NULL DEFAULT false,
    "etims_enabled" BOOLEAN NOT NULL DEFAULT false,
    "tax_provider" TEXT NOT NULL DEFAULT 'risiti',
    "risiti_merchant_id" TEXT,
    "payhero_channel_id" INTEGER,
    "payhero_credential_id" TEXT,
    "mpesa_qr_cpi" TEXT,
    "mpesa_qr_trx_code" TEXT,
    "tin" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "business_context" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "app_profile" TEXT NOT NULL,
    "primary_activity_code" TEXT,
    "primary_activity_status" TEXT NOT NULL DEFAULT 'pending',
    "activity_scheme" TEXT,
    "activity_version" TEXT,
    "secondary_activity_codes" JSONB NOT NULL DEFAULT '[]',
    "operator_roles" JSONB NOT NULL DEFAULT '[]',
    "sales_channels" JSONB NOT NULL DEFAULT '[]',
    "county_code" TEXT,
    "settlement_context" TEXT NOT NULL DEFAULT 'unknown',
    "field_provenance" JSONB NOT NULL DEFAULT '{}',
    "confirmed_at" DATETIME,
    "schema_version" INTEGER NOT NULL DEFAULT 1,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "business_context_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "tax_entities" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "legal_form" TEXT NOT NULL,
    "display_label" TEXT NOT NULL,
    "kra_pin_ciphertext" TEXT,
    "kra_pin_last4" TEXT,
    "registered_tax_obligations" JSONB NOT NULL DEFAULT '[]',
    "accounting_period_start_month" INTEGER NOT NULL DEFAULT 1,
    "status" TEXT NOT NULL DEFAULT 'needs_review',
    "etims_onboarding_status" TEXT NOT NULL DEFAULT 'not_started',
    "etims_method" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "vat_returns" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tax_entity_id" TEXT NOT NULL,
    "period_start" DATETIME NOT NULL,
    "period_end" DATETIME NOT NULL,
    "output_vat" DECIMAL NOT NULL DEFAULT 0,
    "eligible_input_vat" DECIMAL NOT NULL DEFAULT 0,
    "withholding_vat_credit" DECIMAL NOT NULL DEFAULT 0,
    "adjustments" DECIMAL NOT NULL DEFAULT 0,
    "net_payable" DECIMAL NOT NULL DEFAULT 0,
    "evidence" JSONB NOT NULL DEFAULT '{}',
    "status" TEXT NOT NULL DEFAULT 'prepared',
    "submitted_at" DATETIME,
    "accepted_at" DATETIME,
    "paid_at" DATETIME,
    "rejection_reason" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "vat_returns_tax_entity_id_fkey" FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "tot_returns" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tax_entity_id" TEXT NOT NULL,
    "period_start" DATETIME NOT NULL,
    "period_end" DATETIME NOT NULL,
    "gross_sales" DECIMAL NOT NULL DEFAULT 0,
    "rate_basis_points" INTEGER,
    "estimate" DECIMAL NOT NULL DEFAULT 0,
    "evidence" JSONB NOT NULL DEFAULT '{}',
    "status" TEXT NOT NULL DEFAULT 'prepared',
    "submitted_at" DATETIME,
    "accepted_at" DATETIME,
    "paid_at" DATETIME,
    "rejection_reason" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "tot_returns_tax_entity_id_fkey" FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "tax_return_events" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tax_entity_id" TEXT NOT NULL,
    "vat_return_id" TEXT,
    "tot_return_id" TEXT,
    "from_status" TEXT,
    "to_status" TEXT NOT NULL,
    "actor_id" TEXT NOT NULL,
    "note" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "tax_return_events_tax_entity_id_fkey" FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "tax_return_events_vat_return_id_fkey" FOREIGN KEY ("vat_return_id") REFERENCES "vat_returns" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "tax_return_events_tot_return_id_fkey" FOREIGN KEY ("tot_return_id") REFERENCES "tot_returns" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "shop_tax_entities" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "tax_entity_id" TEXT NOT NULL,
    "outlet_reference" TEXT,
    "effective_from" DATETIME NOT NULL,
    "effective_to" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "shop_tax_entities_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "shop_tax_entities_tax_entity_id_fkey" FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "tax_rules" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tax_entity_id" TEXT NOT NULL,
    "tax_type" TEXT NOT NULL,
    "scope" TEXT NOT NULL,
    "jurisdiction" TEXT NOT NULL DEFAULT 'KE',
    "rate_basis_points" INTEGER,
    "tax_base" TEXT NOT NULL,
    "filing_frequency" TEXT NOT NULL DEFAULT 'none',
    "filing_due_day" INTEGER,
    "threshold_minor" DECIMAL,
    "effective_from" DATETIME NOT NULL,
    "effective_to" DATETIME,
    "source_url" TEXT NOT NULL,
    "source_reference" TEXT,
    "reviewed_at" DATETIME,
    "approved_by" TEXT,
    "approval_note" TEXT,
    "status" TEXT NOT NULL DEFAULT 'needs_review',
    "version" INTEGER NOT NULL DEFAULT 1,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "tax_rules_tax_entity_id_fkey" FOREIGN KEY ("tax_entity_id") REFERENCES "tax_entities" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "cloud_backups" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "workspace_key" TEXT NOT NULL,
    "kind" TEXT NOT NULL DEFAULT 'device_bound',
    "snapshot_hash" TEXT,
    "payload" TEXT NOT NULL,
    "storage_key" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "cloud_backups_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "commercial_contributions" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "batch_id" TEXT NOT NULL,
    "record_id" TEXT NOT NULL,
    "policy_version" TEXT NOT NULL,
    "schema_version" TEXT NOT NULL,
    "business_profile" TEXT NOT NULL,
    "period_start" DATETIME NOT NULL,
    "period_end" DATETIME NOT NULL,
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
    "status" TEXT NOT NULL DEFAULT 'accepted',
    "consent_purpose_version" TEXT NOT NULL,
    "quality_flags" JSONB NOT NULL DEFAULT '[]',
    "payload_checksum" TEXT NOT NULL,
    "aggregation_job_version" TEXT,
    "dataset_snapshot_id" TEXT,
    "partner_export_refs" JSONB NOT NULL DEFAULT '[]',
    "supersedes_record_id" TEXT,
    "retention_state" TEXT NOT NULL DEFAULT 'active',
    "deleted_at" DATETIME,
    "accepted_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "customers" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "local_uuid" TEXT NOT NULL,
    "name" TEXT NOT NULL,
    "phone" TEXT,
    "tin" TEXT,
    "notes" TEXT,
    "credit_limit_minor" INTEGER,
    "balance_minor" INTEGER NOT NULL,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" DATETIME NOT NULL,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "customers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "credit_ledger" (
    "id" TEXT NOT NULL PRIMARY KEY,
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
    "created_at" DATETIME NOT NULL,
    CONSTRAINT "credit_ledger_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "credit_ledger_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "customers" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sync_records" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "device_id" TEXT NOT NULL DEFAULT 'legacy',
    "local_id" INTEGER NOT NULL,
    "payload" JSONB NOT NULL,
    "created_at" DATETIME NOT NULL,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "sync_records_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sale_sync_conflicts" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT NOT NULL,
    "local_id" INTEGER NOT NULL,
    "payload" JSONB NOT NULL,
    "reason" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'open',
    "resolution" TEXT,
    "resolved_by" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "resolved_at" DATETIME,
    CONSTRAINT "sale_sync_conflicts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "users" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "email_verified_at" DATETIME,
    "failed_login_attempts" INTEGER NOT NULL DEFAULT 0,
    "locked_until" DATETIME,
    "refresh_token_rotated_at" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "profiles" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "user_id" TEXT,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "name" TEXT NOT NULL,
    "username" TEXT,
    "email" TEXT,
    "photo_url" TEXT,
    "pin_hash" TEXT,
    "role" TEXT NOT NULL DEFAULT 'cashier',
    "active" BOOLEAN NOT NULL DEFAULT true,
    "deleted_at" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "refresh_token_hash" TEXT,
    "refresh_token_previous_hash" TEXT,
    "refresh_token_expires_at" DATETIME,
    "refresh_token_tier" TEXT,
    "refresh_token_rotated_at" DATETIME,
    CONSTRAINT "profiles_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "profiles_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "tenant_subscriptions" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "price_minor" INTEGER,
    "currency" TEXT NOT NULL DEFAULT 'KES',
    "billing_interval" TEXT NOT NULL DEFAULT 'monthly',
    "current_period_end" DATETIME,
    "grace_until" DATETIME,
    "voucher_id" TEXT,
    "updated_by" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "tenant_subscriptions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "tenant_subscriptions_voucher_id_fkey" FOREIGN KEY ("voucher_id") REFERENCES "access_vouchers" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "access_vouchers" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "code_hash" TEXT NOT NULL,
    "code_prefix" TEXT NOT NULL,
    "tenant_id" TEXT,
    "issued_to_profile_id" TEXT,
    "issued_to_email" TEXT,
    "expires_at" DATETIME,
    "redeemed_at" DATETIME,
    "redeemed_by_profile_id" TEXT,
    "revoked_at" DATETIME,
    "paused_at" DATETIME,
    "deleted_at" DATETIME,
    "auto_issued" BOOLEAN NOT NULL DEFAULT false,
    "created_by" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "access_vouchers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "access_vouchers_issued_to_profile_id_fkey" FOREIGN KEY ("issued_to_profile_id") REFERENCES "profiles" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "access_vouchers_redeemed_by_profile_id_fkey" FOREIGN KEY ("redeemed_by_profile_id") REFERENCES "profiles" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "subscription_payments" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "phone_number" TEXT NOT NULL,
    "amount_minor" INTEGER NOT NULL,
    "duration_months" INTEGER NOT NULL DEFAULT 1,
    "status" TEXT NOT NULL DEFAULT 'PENDING',
    "checkout_request_id" TEXT,
    "provider_status" TEXT,
    "mpesa_receipt_code" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "subscription_payments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "products" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "remote_id" TEXT,
    "sync_key" TEXT,
    "name" TEXT NOT NULL,
    "category" TEXT NOT NULL DEFAULT 'General',
    "cost_price" DECIMAL NOT NULL DEFAULT 0,
    "sell_price" DECIMAL NOT NULL DEFAULT 0,
    "stock_qty" DECIMAL NOT NULL DEFAULT 0,
    "reorder_level" INTEGER NOT NULL DEFAULT 0,
    "bottle_ml" INTEGER NOT NULL DEFAULT 750,
    "unit" TEXT NOT NULL DEFAULT 'each',
    "ml_per_kg" DECIMAL NOT NULL DEFAULT 0,
    "product_uuid" TEXT,
    "item_kind" TEXT NOT NULL DEFAULT 'unknown',
    "gpc_code" TEXT,
    "gpc_version" TEXT,
    "gpc_mapping_status" TEXT NOT NULL DEFAULT 'unmapped',
    "gtin" TEXT,
    "merchant_sku" TEXT,
    "brand_entity_id" TEXT,
    "brand_label_local" TEXT,
    "manufacturer_entity_id" TEXT,
    "variant_attributes" JSONB,
    "external_unit_code" TEXT,
    "unit_scheme" TEXT,
    "unit_version" TEXT,
    "unit_mapping_status" TEXT NOT NULL DEFAULT 'unknown',
    "pack_quantity" DECIMAL,
    "pack_unit_code" TEXT,
    "identity_provenance" TEXT NOT NULL DEFAULT 'system_derived',
    "half_price" DECIMAL,
    "quarter_price" DECIMAL,
    "excise_stamp_batch" TEXT,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "products_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sales" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "device_id" TEXT NOT NULL DEFAULT 'legacy',
    "staff_id" TEXT NOT NULL,
    "staff_name" TEXT NOT NULL,
    "buyer_name" TEXT,
    "buyer_tin" TEXT,
    "payment_method" TEXT NOT NULL DEFAULT 'cash',
    "payment_reference" TEXT,
    "total" DECIMAL NOT NULL DEFAULT 0,
    "profit" DECIMAL NOT NULL DEFAULT 0,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "sales_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "sales_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "profiles" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sale_evidence" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "sale_id" TEXT,
    "device_id" TEXT NOT NULL DEFAULT 'legacy',
    "local_id" INTEGER NOT NULL,
    "object_key" TEXT NOT NULL,
    "public_url" TEXT,
    "mime_type" TEXT NOT NULL,
    "byte_size" INTEGER,
    "created_by" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "sale_evidence_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "sale_evidence_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "sales" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sale_payments" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "sale_id" TEXT NOT NULL,
    "local_uuid" TEXT NOT NULL,
    "method" TEXT NOT NULL,
    "amount" DECIMAL NOT NULL,
    "tendered" DECIMAL,
    "change" DECIMAL,
    "reference" TEXT,
    "status" TEXT NOT NULL DEFAULT 'confirmed',
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "sale_payments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT "sale_payments_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "sales" ("id") ON DELETE CASCADE ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "sale_items" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "sale_id" TEXT NOT NULL,
    "product_id" TEXT,
    "product_name" TEXT NOT NULL,
    "qty" DECIMAL NOT NULL,
    "unit_price" DECIMAL NOT NULL,
    "unit_cost" DECIMAL NOT NULL,
    "vat_amount" DECIMAL,
    "taxable_amount" DECIMAL,
    "tax_class" TEXT,
    "vat_rate_bps" INTEGER,
    "tax_rule_id" TEXT,
    "tax_rule_version" INTEGER,
    "portion" TEXT NOT NULL DEFAULT 'full',
    "portion_ml" INTEGER NOT NULL DEFAULT 0,
    CONSTRAINT "sale_items_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "sale_items_sale_id_fkey" FOREIGN KEY ("sale_id") REFERENCES "sales" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "sale_items_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products" ("id") ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT "sale_items_tax_rule_id_fkey" FOREIGN KEY ("tax_rule_id") REFERENCES "tax_rules" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "stock_adjustments" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "product_id" TEXT NOT NULL,
    "delta" DECIMAL NOT NULL,
    "reason" TEXT,
    "staff_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "stock_adjustments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "stock_adjustments_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "stock_adjustments_staff_id_fkey" FOREIGN KEY ("staff_id") REFERENCES "profiles" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "payments" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "initiated_by" TEXT NOT NULL,
    "staff_name" TEXT NOT NULL,
    "reference" TEXT NOT NULL,
    "phone_number" TEXT NOT NULL,
    "amount" DECIMAL NOT NULL,
    "cart_snapshot" JSONB NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'QUEUED',
    "checkout_request_id" TEXT,
    "payment_mode" TEXT NOT NULL DEFAULT 'stk',
    "qr_code_data" TEXT,
    "provider_status" TEXT,
    "provider_checked_at" DATETIME,
    "sale_id" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "payments_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "payments_initiated_by_fkey" FOREIGN KEY ("initiated_by") REFERENCES "profiles" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "deletion_ledgers" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "subject_type" TEXT NOT NULL,
    "subject_id" TEXT NOT NULL,
    "reason" TEXT,
    "completed_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "deletion_ledgers_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "verification_challenges" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT,
    "email" TEXT NOT NULL,
    "code" TEXT NOT NULL,
    "expires_at" DATETIME NOT NULL,
    "used" BOOLEAN NOT NULL DEFAULT false,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "verification_challenges_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "app_sessions" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "access_token" TEXT NOT NULL,
    "refresh_token" TEXT NOT NULL,
    "expires_at" DATETIME NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "app_sessions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "etims_devices" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "tin" TEXT NOT NULL,
    "device_id" TEXT NOT NULL,
    "device_name" TEXT,
    "device_serial" TEXT,
    "status" TEXT NOT NULL DEFAULT 'unregistered',
    "access_key" TEXT,
    "encryption_key" TEXT,
    "initialised_at" DATETIME,
    "last_error" TEXT,
    "registered_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "etims_devices_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "etims_receipts" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "receipt_number" TEXT NOT NULL,
    "kra_receipt_number" TEXT,
    "verification_url" TEXT,
    "qr_payload" TEXT,
    "status" TEXT NOT NULL DEFAULT 'pending',
    "documentType" TEXT NOT NULL DEFAULT 'invoice',
    "original_receipt_number" TEXT,
    "return_number" TEXT,
    "payload" JSONB NOT NULL,
    "total" TEXT,
    "vat_total" TEXT,
    "vat_rate_percent" REAL,
    "item_count" INTEGER,
    "payment_method" TEXT,
    "payment_reference" TEXT,
    "rejection_reason" TEXT,
    "device_id" TEXT,
    "issued_at" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "etims_receipts_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "etims_receipts_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "etims_devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "etims_z_reports" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT,
    "z_number" INTEGER NOT NULL,
    "business_date" DATETIME NOT NULL,
    "invoice_count" INTEGER NOT NULL DEFAULT 0,
    "total" TEXT NOT NULL DEFAULT '0.00',
    "vat_total" TEXT NOT NULL DEFAULT '0.00',
    "pending_count" INTEGER NOT NULL DEFAULT 0,
    "rejected_count" INTEGER NOT NULL DEFAULT 0,
    "status" TEXT NOT NULL DEFAULT 'issued',
    "failure_reason" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "etims_z_reports_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "etims_z_reports_device_id_fkey" FOREIGN KEY ("device_id") REFERENCES "etims_devices" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "telemetry_events" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "client_event_id" TEXT,
    "tenant_id" TEXT NOT NULL,
    "deviceId" TEXT,
    "session_jti" TEXT,
    "name" TEXT NOT NULL,
    "at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "route" TEXT,
    "detail" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "telemetry_events_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "churn_snapshots" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT,
    "date" DATETIME NOT NULL,
    "streak_days" INTEGER NOT NULL,
    "days_since_last_active" INTEGER NOT NULL,
    "total_sessions" INTEGER NOT NULL,
    "risk" TEXT NOT NULL,
    "score" REAL NOT NULL,
    "computed_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "churn_snapshots_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "admin_audit_logs" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "adminId" TEXT NOT NULL,
    "action" TEXT NOT NULL,
    "targetType" TEXT,
    "target_id" TEXT,
    "tenantId" TEXT,
    "at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- CreateTable
CREATE TABLE "device_diagnostics" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT,
    "device_id" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "osVersion" TEXT NOT NULL,
    "appVersion" TEXT NOT NULL,
    "buildNumber" TEXT NOT NULL,
    "locale" TEXT NOT NULL,
    "manufacturer" TEXT,
    "model" TEXT,
    "crashCount" INTEGER NOT NULL DEFAULT 0,
    "errorCount" INTEGER NOT NULL DEFAULT 0,
    "warningCount" INTEGER NOT NULL DEFAULT 0,
    "first_seen" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_seen" DATETIME NOT NULL,
    CONSTRAINT "device_diagnostics_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "device_crash_entries" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "diagnostic_id" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "message" TEXT NOT NULL,
    "stack" TEXT,
    "route" TEXT,
    "actorName" TEXT,
    "action" TEXT,
    "breadcrumbs" TEXT,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "session_jti" TEXT,
    "client_event_id" TEXT,
    CONSTRAINT "device_crash_entries_diagnostic_id_fkey" FOREIGN KEY ("diagnostic_id") REFERENCES "device_diagnostics" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "system_settings" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "key" TEXT NOT NULL,
    "value" TEXT NOT NULL,
    "description" TEXT,
    "updated_at" DATETIME NOT NULL
);

-- CreateTable
CREATE TABLE "support_tickets" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "device_id" TEXT,
    "type" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "description" TEXT NOT NULL,
    "status" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "support_tickets_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "product_variants" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "local_id" INTEGER,
    "sync_key" TEXT,
    "remote_id" TEXT,
    "product_id" TEXT NOT NULL,
    "variant_name" TEXT NOT NULL,
    "sku" TEXT NOT NULL,
    "unit" TEXT NOT NULL DEFAULT 'each',
    "size_ml" INTEGER NOT NULL DEFAULT 0,
    "sell_price" DECIMAL NOT NULL DEFAULT 0,
    "cost_price" DECIMAL NOT NULL DEFAULT 0,
    "stock_qty" DECIMAL NOT NULL DEFAULT 0,
    "reserved_qty" DECIMAL NOT NULL DEFAULT 0,
    "reorder_level" INTEGER NOT NULL DEFAULT 0,
    "position" INTEGER NOT NULL DEFAULT 0,
    "active" BOOLEAN NOT NULL DEFAULT true,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "product_variants_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT "product_variants_product_id_fkey" FOREIGN KEY ("product_id") REFERENCES "products" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "cost_pools" (
    "id" TEXT NOT NULL PRIMARY KEY,
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
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "cost_pools_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "owner_transactions" (
    "id" TEXT NOT NULL PRIMARY KEY,
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
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "owner_transactions_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "mpesa_incoming" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "remote_id" TEXT NOT NULL,
    "trans_id" TEXT NOT NULL,
    "amount" REAL NOT NULL,
    "payer_label" TEXT NOT NULL,
    "bill_ref" TEXT,
    "received_at" DATETIME NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "status" TEXT NOT NULL DEFAULT 'unclaimed',
    "claimed_by_device" TEXT,
    "claimed_sale_uuid" TEXT,
    "claimed_at" DATETIME,
    "ignored_at" DATETIME,
    "ignore_reason" TEXT,
    CONSTRAINT "mpesa_incoming_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "receipt_links" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "tenant_id" TEXT NOT NULL,
    "token" TEXT NOT NULL,
    "snapshot" JSONB NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "expires_at" DATETIME NOT NULL,
    "revoked_at" DATETIME,
    CONSTRAINT "receipt_links_tenant_id_fkey" FOREIGN KEY ("tenant_id") REFERENCES "tenants" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "admin_keys" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "email" TEXT NOT NULL,
    "phone" TEXT NOT NULL,
    "key_hash" TEXT NOT NULL,
    "created_by" TEXT NOT NULL,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "used_at" DATETIME,
    "expires_at" DATETIME NOT NULL,
    "revoked_at" DATETIME,
    "department" TEXT NOT NULL DEFAULT 'operations',
    "role" TEXT NOT NULL DEFAULT 'worker',
    "permissions" JSONB NOT NULL DEFAULT '[]',
    "can_recruit" BOOLEAN NOT NULL DEFAULT false,
    "can_mint_keys" BOOLEAN NOT NULL DEFAULT false,
    "can_assign_tasks" BOOLEAN NOT NULL DEFAULT false,
    "parent_key_id" TEXT,
    CONSTRAINT "admin_keys_parent_key_id_fkey" FOREIGN KEY ("parent_key_id") REFERENCES "admin_keys" ("id") ON DELETE SET NULL ON UPDATE CASCADE
);

-- CreateTable
CREATE TABLE "admin_tasks" (
    "id" TEXT NOT NULL PRIMARY KEY,
    "title" TEXT NOT NULL,
    "description" TEXT,
    "department" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'assigned',
    "created_by" TEXT NOT NULL,
    "assignee_key_id" TEXT NOT NULL,
    "due_at" DATETIME,
    "created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" DATETIME NOT NULL,
    CONSTRAINT "admin_tasks_assignee_key_id_fkey" FOREIGN KEY ("assignee_key_id") REFERENCES "admin_keys" ("id") ON DELETE RESTRICT ON UPDATE CASCADE
);

-- CreateIndex
CREATE UNIQUE INDEX "business_context_tenant_id_key" ON "business_context"("tenant_id");

-- CreateIndex
CREATE INDEX "business_context_primary_activity_code_idx" ON "business_context"("primary_activity_code");

-- CreateIndex
CREATE INDEX "vat_returns_tax_entity_id_period_start_period_end_idx" ON "vat_returns"("tax_entity_id", "period_start", "period_end");

-- CreateIndex
CREATE INDEX "vat_returns_status_idx" ON "vat_returns"("status");

-- CreateIndex
CREATE UNIQUE INDEX "vat_returns_tax_entity_id_period_start_period_end_key" ON "vat_returns"("tax_entity_id", "period_start", "period_end");

-- CreateIndex
CREATE INDEX "tot_returns_tax_entity_id_period_start_period_end_idx" ON "tot_returns"("tax_entity_id", "period_start", "period_end");

-- CreateIndex
CREATE INDEX "tot_returns_status_idx" ON "tot_returns"("status");

-- CreateIndex
CREATE UNIQUE INDEX "tot_returns_tax_entity_id_period_start_period_end_key" ON "tot_returns"("tax_entity_id", "period_start", "period_end");

-- CreateIndex
CREATE INDEX "tax_return_events_tax_entity_id_created_at_idx" ON "tax_return_events"("tax_entity_id", "created_at");

-- CreateIndex
CREATE INDEX "tax_return_events_vat_return_id_created_at_idx" ON "tax_return_events"("vat_return_id", "created_at");

-- CreateIndex
CREATE INDEX "tax_return_events_tot_return_id_created_at_idx" ON "tax_return_events"("tot_return_id", "created_at");

-- CreateIndex
CREATE INDEX "shop_tax_entities_tenant_id_effective_from_effective_to_idx" ON "shop_tax_entities"("tenant_id", "effective_from", "effective_to");

-- CreateIndex
CREATE INDEX "shop_tax_entities_tax_entity_id_effective_from_effective_to_idx" ON "shop_tax_entities"("tax_entity_id", "effective_from", "effective_to");

-- CreateIndex
CREATE INDEX "tax_rules_tax_entity_id_tax_type_scope_effective_from_effective_to_idx" ON "tax_rules"("tax_entity_id", "tax_type", "scope", "effective_from", "effective_to");

-- CreateIndex
CREATE INDEX "tax_rules_status_effective_from_effective_to_idx" ON "tax_rules"("status", "effective_from", "effective_to");

-- CreateIndex
CREATE INDEX "cloud_backups_tenant_id_workspace_key_kind_created_at_idx" ON "cloud_backups"("tenant_id", "workspace_key", "kind", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "cloud_backups_tenant_id_workspace_key_kind_snapshot_hash_key" ON "cloud_backups"("tenant_id", "workspace_key", "kind", "snapshot_hash");

-- CreateIndex
CREATE UNIQUE INDEX "commercial_contributions_record_id_key" ON "commercial_contributions"("record_id");

-- CreateIndex
CREATE INDEX "commercial_contributions_business_profile_period_start_period_end_idx" ON "commercial_contributions"("business_profile", "period_start", "period_end");

-- CreateIndex
CREATE INDEX "commercial_contributions_batch_id_accepted_at_idx" ON "commercial_contributions"("batch_id", "accepted_at");

-- CreateIndex
CREATE INDEX "customers_tenant_id_name_idx" ON "customers"("tenant_id", "name");

-- CreateIndex
CREATE UNIQUE INDEX "customers_tenant_id_local_uuid_key" ON "customers"("tenant_id", "local_uuid");

-- CreateIndex
CREATE INDEX "credit_ledger_tenant_id_customer_id_created_at_idx" ON "credit_ledger"("tenant_id", "customer_id", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "credit_ledger_tenant_id_local_uuid_key" ON "credit_ledger"("tenant_id", "local_uuid");

-- CreateIndex
CREATE INDEX "sync_records_tenant_id_kind_created_at_idx" ON "sync_records"("tenant_id", "kind", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "sync_records_tenant_id_kind_device_id_local_id_key" ON "sync_records"("tenant_id", "kind", "device_id", "local_id");

-- CreateIndex
CREATE INDEX "sale_sync_conflicts_tenant_id_status_created_at_idx" ON "sale_sync_conflicts"("tenant_id", "status", "created_at");

-- CreateIndex
CREATE UNIQUE INDEX "sale_sync_conflicts_tenant_id_device_id_local_id_key" ON "sale_sync_conflicts"("tenant_id", "device_id", "local_id");

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "profiles_refresh_token_hash_key" ON "profiles"("refresh_token_hash");

-- CreateIndex
CREATE INDEX "profiles_tenant_id_idx" ON "profiles"("tenant_id");

-- CreateIndex
CREATE INDEX "profiles_user_id_idx" ON "profiles"("user_id");

-- CreateIndex
CREATE UNIQUE INDEX "profiles_tenant_id_username_key" ON "profiles"("tenant_id", "username");

-- CreateIndex
CREATE UNIQUE INDEX "tenant_subscriptions_tenant_id_key" ON "tenant_subscriptions"("tenant_id");

-- CreateIndex
CREATE UNIQUE INDEX "tenant_subscriptions_voucher_id_key" ON "tenant_subscriptions"("voucher_id");

-- CreateIndex
CREATE INDEX "tenant_subscriptions_status_current_period_end_idx" ON "tenant_subscriptions"("status", "current_period_end");

-- CreateIndex
CREATE UNIQUE INDEX "access_vouchers_code_hash_key" ON "access_vouchers"("code_hash");

-- CreateIndex
CREATE INDEX "access_vouchers_tenant_id_expires_at_idx" ON "access_vouchers"("tenant_id", "expires_at");

-- CreateIndex
CREATE INDEX "access_vouchers_issued_to_email_idx" ON "access_vouchers"("issued_to_email");

-- CreateIndex
CREATE UNIQUE INDEX "subscription_payments_reference_key" ON "subscription_payments"("reference");

-- CreateIndex
CREATE INDEX "subscription_payments_tenant_id_status_idx" ON "subscription_payments"("tenant_id", "status");

-- CreateIndex
CREATE INDEX "products_tenant_id_idx" ON "products"("tenant_id");

-- CreateIndex
CREATE INDEX "products_item_kind_gpc_mapping_status_idx" ON "products"("item_kind", "gpc_mapping_status");

-- CreateIndex
CREATE UNIQUE INDEX "products_tenant_id_sync_key_key" ON "products"("tenant_id", "sync_key");

-- CreateIndex
CREATE UNIQUE INDEX "products_tenant_id_product_uuid_key" ON "products"("tenant_id", "product_uuid");

-- CreateIndex
CREATE INDEX "sales_tenant_id_idx" ON "sales"("tenant_id");

-- CreateIndex
CREATE INDEX "sales_created_at_idx" ON "sales"("created_at");

-- CreateIndex
CREATE UNIQUE INDEX "sales_tenant_id_device_id_local_id_key" ON "sales"("tenant_id", "device_id", "local_id");

-- CreateIndex
CREATE INDEX "sale_evidence_tenant_id_device_id_local_id_idx" ON "sale_evidence"("tenant_id", "device_id", "local_id");

-- CreateIndex
CREATE UNIQUE INDEX "sale_evidence_tenant_id_device_id_local_id_object_key_key" ON "sale_evidence"("tenant_id", "device_id", "local_id", "object_key");

-- CreateIndex
CREATE INDEX "sale_payments_tenant_id_sale_id_idx" ON "sale_payments"("tenant_id", "sale_id");

-- CreateIndex
CREATE UNIQUE INDEX "sale_payments_tenant_id_local_uuid_key" ON "sale_payments"("tenant_id", "local_uuid");

-- CreateIndex
CREATE INDEX "sale_items_tenant_id_idx" ON "sale_items"("tenant_id");

-- CreateIndex
CREATE INDEX "sale_items_sale_id_idx" ON "sale_items"("sale_id");

-- CreateIndex
CREATE INDEX "sale_items_tax_rule_id_idx" ON "sale_items"("tax_rule_id");

-- CreateIndex
CREATE INDEX "stock_adjustments_tenant_id_idx" ON "stock_adjustments"("tenant_id");

-- CreateIndex
CREATE UNIQUE INDEX "payments_reference_key" ON "payments"("reference");

-- CreateIndex
CREATE INDEX "payments_tenant_id_idx" ON "payments"("tenant_id");

-- CreateIndex
CREATE INDEX "payments_reference_idx" ON "payments"("reference");

-- CreateIndex
CREATE INDEX "deletion_ledgers_tenant_id_idx" ON "deletion_ledgers"("tenant_id");

-- CreateIndex
CREATE INDEX "verification_challenges_email_idx" ON "verification_challenges"("email");

-- CreateIndex
CREATE INDEX "verification_challenges_code_idx" ON "verification_challenges"("code");

-- CreateIndex
CREATE INDEX "verification_challenges_expires_at_idx" ON "verification_challenges"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "app_sessions_refresh_token_key" ON "app_sessions"("refresh_token");

-- CreateIndex
CREATE INDEX "app_sessions_refresh_token_idx" ON "app_sessions"("refresh_token");

-- CreateIndex
CREATE INDEX "app_sessions_expires_at_idx" ON "app_sessions"("expires_at");

-- CreateIndex
CREATE UNIQUE INDEX "etims_devices_tenant_id_key" ON "etims_devices"("tenant_id");

-- CreateIndex
CREATE UNIQUE INDEX "etims_devices_device_id_key" ON "etims_devices"("device_id");

-- CreateIndex
CREATE INDEX "etims_devices_tenant_id_idx" ON "etims_devices"("tenant_id");

-- CreateIndex
CREATE INDEX "etims_devices_device_id_idx" ON "etims_devices"("device_id");

-- CreateIndex
CREATE UNIQUE INDEX "etims_receipts_kra_receipt_number_key" ON "etims_receipts"("kra_receipt_number");

-- CreateIndex
CREATE INDEX "etims_receipts_tenant_id_idx" ON "etims_receipts"("tenant_id");

-- CreateIndex
CREATE INDEX "etims_receipts_kra_receipt_number_idx" ON "etims_receipts"("kra_receipt_number");

-- CreateIndex
CREATE INDEX "etims_receipts_device_id_idx" ON "etims_receipts"("device_id");

-- CreateIndex
CREATE INDEX "etims_receipts_status_idx" ON "etims_receipts"("status");

-- CreateIndex
CREATE INDEX "etims_receipts_created_at_idx" ON "etims_receipts"("created_at");

-- CreateIndex
CREATE UNIQUE INDEX "etims_receipts_tenant_id_receipt_number_key" ON "etims_receipts"("tenant_id", "receipt_number");

-- CreateIndex
CREATE UNIQUE INDEX "etims_receipts_tenant_id_return_number_key" ON "etims_receipts"("tenant_id", "return_number");

-- CreateIndex
CREATE INDEX "etims_z_reports_tenant_id_idx" ON "etims_z_reports"("tenant_id");

-- CreateIndex
CREATE INDEX "etims_z_reports_business_date_idx" ON "etims_z_reports"("business_date");

-- CreateIndex
CREATE UNIQUE INDEX "etims_z_reports_tenant_id_business_date_key" ON "etims_z_reports"("tenant_id", "business_date");

-- CreateIndex
CREATE UNIQUE INDEX "telemetry_events_client_event_id_key" ON "telemetry_events"("client_event_id");

-- CreateIndex
CREATE INDEX "telemetry_events_tenant_id_idx" ON "telemetry_events"("tenant_id");

-- CreateIndex
CREATE INDEX "telemetry_events_name_idx" ON "telemetry_events"("name");

-- CreateIndex
CREATE INDEX "telemetry_events_at_idx" ON "telemetry_events"("at");

-- CreateIndex
CREATE INDEX "telemetry_events_created_at_idx" ON "telemetry_events"("created_at");

-- CreateIndex
CREATE INDEX "telemetry_events_session_jti_at_idx" ON "telemetry_events"("session_jti", "at");

-- CreateIndex
CREATE INDEX "churn_snapshots_tenant_id_idx" ON "churn_snapshots"("tenant_id");

-- CreateIndex
CREATE INDEX "churn_snapshots_date_idx" ON "churn_snapshots"("date");

-- CreateIndex
CREATE INDEX "churn_snapshots_computed_at_idx" ON "churn_snapshots"("computed_at");

-- CreateIndex
CREATE INDEX "admin_audit_logs_adminId_idx" ON "admin_audit_logs"("adminId");

-- CreateIndex
CREATE INDEX "admin_audit_logs_tenantId_idx" ON "admin_audit_logs"("tenantId");

-- CreateIndex
CREATE INDEX "admin_audit_logs_at_idx" ON "admin_audit_logs"("at");

-- CreateIndex
CREATE INDEX "device_diagnostics_tenant_id_idx" ON "device_diagnostics"("tenant_id");

-- CreateIndex
CREATE INDEX "device_diagnostics_last_seen_idx" ON "device_diagnostics"("last_seen");

-- CreateIndex
CREATE UNIQUE INDEX "device_diagnostics_device_id_key" ON "device_diagnostics"("device_id");

-- CreateIndex
CREATE INDEX "device_crash_entries_diagnostic_id_idx" ON "device_crash_entries"("diagnostic_id");

-- CreateIndex
CREATE INDEX "device_crash_entries_created_at_idx" ON "device_crash_entries"("created_at");

-- CreateIndex
CREATE INDEX "device_crash_entries_session_jti_idx" ON "device_crash_entries"("session_jti");

-- CreateIndex
CREATE UNIQUE INDEX "device_crash_entries_diagnostic_id_client_event_id_key" ON "device_crash_entries"("diagnostic_id", "client_event_id");

-- CreateIndex
CREATE UNIQUE INDEX "system_settings_key_key" ON "system_settings"("key");

-- CreateIndex
CREATE INDEX "system_settings_key_idx" ON "system_settings"("key");

-- CreateIndex
CREATE INDEX "support_tickets_tenant_id_idx" ON "support_tickets"("tenant_id");

-- CreateIndex
CREATE INDEX "support_tickets_type_idx" ON "support_tickets"("type");

-- CreateIndex
CREATE INDEX "support_tickets_status_idx" ON "support_tickets"("status");

-- CreateIndex
CREATE INDEX "support_tickets_created_at_idx" ON "support_tickets"("created_at");

-- CreateIndex
CREATE INDEX "product_variants_tenant_id_idx" ON "product_variants"("tenant_id");

-- CreateIndex
CREATE INDEX "product_variants_product_id_idx" ON "product_variants"("product_id");

-- CreateIndex
CREATE UNIQUE INDEX "product_variants_tenant_id_sync_key_key" ON "product_variants"("tenant_id", "sync_key");

-- CreateIndex
CREATE UNIQUE INDEX "product_variants_tenant_id_product_id_local_id_key" ON "product_variants"("tenant_id", "product_id", "local_id");

-- CreateIndex
CREATE INDEX "cost_pools_tenant_id_idx" ON "cost_pools"("tenant_id");

-- CreateIndex
CREATE INDEX "cost_pools_status_idx" ON "cost_pools"("status");

-- CreateIndex
CREATE UNIQUE INDEX "cost_pools_tenant_id_sync_key_key" ON "cost_pools"("tenant_id", "sync_key");

-- CreateIndex
CREATE UNIQUE INDEX "cost_pools_tenant_id_uuid_key" ON "cost_pools"("tenant_id", "uuid");

-- CreateIndex
CREATE INDEX "owner_transactions_tenant_id_idx" ON "owner_transactions"("tenant_id");

-- CreateIndex
CREATE INDEX "owner_transactions_transaction_type_idx" ON "owner_transactions"("transaction_type");

-- CreateIndex
CREATE INDEX "owner_transactions_created_at_idx" ON "owner_transactions"("created_at");

-- CreateIndex
CREATE UNIQUE INDEX "owner_transactions_tenant_id_sync_key_key" ON "owner_transactions"("tenant_id", "sync_key");

-- CreateIndex
CREATE UNIQUE INDEX "owner_transactions_tenant_id_uuid_key" ON "owner_transactions"("tenant_id", "uuid");

-- CreateIndex
CREATE UNIQUE INDEX "mpesa_incoming_remote_id_key" ON "mpesa_incoming"("remote_id");

-- CreateIndex
CREATE UNIQUE INDEX "mpesa_incoming_trans_id_key" ON "mpesa_incoming"("trans_id");

-- CreateIndex
CREATE INDEX "mpesa_incoming_tenant_id_received_at_idx" ON "mpesa_incoming"("tenant_id", "received_at");

-- CreateIndex
CREATE INDEX "mpesa_incoming_status_idx" ON "mpesa_incoming"("status");

-- CreateIndex
CREATE UNIQUE INDEX "receipt_links_token_key" ON "receipt_links"("token");

-- CreateIndex
CREATE INDEX "receipt_links_tenant_id_idx" ON "receipt_links"("tenant_id");

-- CreateIndex
CREATE INDEX "receipt_links_expires_at_idx" ON "receipt_links"("expires_at");

-- CreateIndex
CREATE INDEX "admin_keys_email_phone_idx" ON "admin_keys"("email", "phone");

-- CreateIndex
CREATE INDEX "admin_keys_email_idx" ON "admin_keys"("email");

-- CreateIndex
CREATE INDEX "admin_keys_parent_key_id_idx" ON "admin_keys"("parent_key_id");

-- CreateIndex
CREATE INDEX "admin_tasks_assignee_key_id_status_idx" ON "admin_tasks"("assignee_key_id", "status");

-- CreateIndex
CREATE INDEX "admin_tasks_department_created_at_idx" ON "admin_tasks"("department", "created_at");
