/**
 * The commercial-intelligence purpose is a separate policy from owner backup,
 * financial evidence, telemetry and lender-authorized sharing. This contract
 * is intentionally disabled until disclosure, consent and legal approval are
 * recorded; defining an allowlist must never be interpreted as permission to
 * collect by default.
 */
export const COMMERCIAL_POLICY = Object.freeze({
  policyId: 'commercial-intelligence',
  version: 'v1-draft',
  status: 'disabled_pending_approval',
  collectionEnabled: false,
  purpose:
    'Produce aggregated Kenyan commerce trend insights for approved business and research uses; never sell or expose an individual shop, customer, receipt, or source transaction.',
  disclosure:
    'Commercial sharing is separate from owner backup and financial evidence. POS checkout and owner analytics work when commercial sharing is off.',
  allowlist: Object.freeze([
    'period_start_utc',
    'period_end_utc',
    'business_profile',
    'category_family',
    'unit_kind',
    'currency',
    'transaction_count',
    'gross_revenue_minor_aggregate',
    'discount_minor_aggregate',
    'refund_minor_aggregate',
    'cogs_minor_aggregate',
    'stockout_count_aggregate',
    'payment_method_mix_aggregate',
    'coverage_level',
    'schema_version',
  ]),
  prohibited: Object.freeze([
    'customer_name',
    'customer_phone',
    'customer_tin',
    'prescription_text',
    'free_form_notes',
    'photo',
    'product_name',
    'receipt_number',
    'exact_shop_id',
    'source_transaction_id',
    'stable_contributor_token_in_partner_output',
  ]),
});

export type CommercialPolicy = typeof COMMERCIAL_POLICY;
