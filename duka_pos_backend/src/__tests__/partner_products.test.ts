import { describe, expect, it } from 'vitest';
import { buildPartnerProductCell } from '../lib/partner_products';

describe('fixed partner data products', () => {
  it('suppresses NGO and manufacturer cells below the 10-business guardrail', () => {
    const ngo = buildPartnerProductCell({
      productId: 'ngo_digitisation_pulse',
      periodStartUtc: '2026-10-01T00:00:00Z',
      periodEndUtc: '2026-11-01T00:00:00Z',
      geography: 'national',
      categoryCode: 'MULTI_CATEGORY',
      contributingBusinesses: 9,
      underlyingTransactions: 500,
      metrics: { sale_record_coverage: 0.8 },
      methodology: 'Synthetic fixture',
    });
    expect(ngo.suppressed).toBe(true);
    expect(ngo.suppressionReason).toContain('minimum_business_threshold');
    expect(ngo.metrics).toEqual({});

    const manufacturer = buildPartnerProductCell({
      productId: 'manufacturer_category_brand_demand',
      periodStartUtc: '2026-10-01T00:00:00Z',
      periodEndUtc: '2026-11-01T00:00:00Z',
      geography: 'county',
      categoryCode: '10000001',
      contributingBusinesses: 12,
      underlyingTransactions: 99,
      metrics: { net_sales_minor: 100000 },
      methodology: 'Synthetic fixture',
    });
    expect(manufacturer.suppressed).toBe(true);
    expect(manufacturer.suppressionReason).toContain('minimum_transaction_threshold');
  });

  it('publishes supplier category metrics only at both disclosure thresholds', () => {
    const supplier = buildPartnerProductCell({
      productId: 'supplier_replenishment_supply',
      periodStartUtc: '2026-10-01T00:00:00Z',
      periodEndUtc: '2026-11-01T00:00:00Z',
      geography: 'national',
      categoryCode: '10000001',
      contributingBusinesses: 10,
      underlyingTransactions: 100,
      metrics: { fill_rate: 0.92, lead_time_median_days: 3 },
      methodology: 'Synthetic fixture',
    });
    expect(supplier.suppressed).toBe(false);
    expect(supplier.suppressionReason).toBeNull();
    expect(supplier.metrics).toEqual({ fill_rate: 0.92, lead_time_median_days: 3 });
  });

  it('keeps prohibited partner dimensions in the disclosure allowlist, never output', () => {
    const output = buildPartnerProductCell({
      productId: 'manufacturer_category_brand_demand',
      periodStartUtc: '2026-10-01T00:00:00Z',
      periodEndUtc: '2026-11-01T00:00:00Z',
      geography: 'county',
      categoryCode: '10000001',
      contributingBusinesses: 10,
      underlyingTransactions: 100,
      metrics: { category_units: 500 },
      methodology: 'Synthetic fixture',
    });
    expect(output.metrics).not.toHaveProperty('shop_id');
    expect(output.disclosure.prohibitedDimensions).toContain('exact_price');
  });
});
