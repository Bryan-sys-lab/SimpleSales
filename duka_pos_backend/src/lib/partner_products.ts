export const PARTNER_DISCLOSURE_THRESHOLDS = Object.freeze({
  minimumBusinesses: 10,
  minimumTransactions: 100,
});

export type PartnerProductKind =
  | 'ngo_digitisation_pulse'
  | 'manufacturer_category_brand_demand'
  | 'supplier_replenishment_supply';

export type PartnerCellInput = {
  productId: PartnerProductKind;
  periodStartUtc: string;
  periodEndUtc: string;
  geography: 'county' | 'region' | 'national';
  categoryCode: string;
  contributingBusinesses: number;
  underlyingTransactions: number;
  metrics: Record<string, number | null>;
  methodology: string;
};

export type PartnerProductOutput = {
  productId: PartnerProductKind;
  productName: string;
  period: { startUtc: string; endUtc: string };
  geography: PartnerCellInput['geography'];
  categoryCode: string;
  suppressed: boolean;
  suppressionReason: string | null;
  metrics: Record<string, number | null>;
  disclosure: {
    minimumBusinesses: number;
    minimumTransactions: number;
    prohibitedDimensions: readonly string[];
  };
  methodology: string;
};

const names: Record<PartnerProductKind, string> = {
  ngo_digitisation_pulse: 'SME Digitisation & Market Activity Pulse',
  manufacturer_category_brand_demand: 'Category / Brand Demand Pulse',
  supplier_replenishment_supply: 'Replenishment & Category Supply Pulse',
};

const prohibited: Record<PartnerProductKind, readonly string[]> = {
  ngo_digitisation_pulse: ['shop_id', 'beneficiary_id', 'customer_id', 'staff_id', 'exact_location'],
  manufacturer_category_brand_demand: ['shop_id', 'exact_price', 'exact_stock', 'basket', 'competitor_store'],
  supplier_replenishment_supply: ['supplier_contact', 'shop_supplier_relationship', 'private_terms', 'exact_shop'],
};

export function buildPartnerProductCell(input: PartnerCellInput): PartnerProductOutput {
  if (input.periodStartUtc >= input.periodEndUtc) throw new Error('Invalid partner product period');
  if (input.contributingBusinesses < 0 || input.underlyingTransactions < 0) {
    throw new Error('Partner cohort counts must be non-negative');
  }
  const reasons: string[] = [];
  if (input.contributingBusinesses < PARTNER_DISCLOSURE_THRESHOLDS.minimumBusinesses) {
    reasons.push('minimum_business_threshold');
  }
  if (input.underlyingTransactions < PARTNER_DISCLOSURE_THRESHOLDS.minimumTransactions) {
    reasons.push('minimum_transaction_threshold');
  }
  return {
    productId: input.productId,
    productName: names[input.productId],
    period: { startUtc: input.periodStartUtc, endUtc: input.periodEndUtc },
    geography: input.geography,
    categoryCode: input.categoryCode,
    suppressed: reasons.length > 0,
    suppressionReason: reasons.length ? reasons.join(',') : null,
    metrics: reasons.length ? {} : input.metrics,
    disclosure: {
      minimumBusinesses: PARTNER_DISCLOSURE_THRESHOLDS.minimumBusinesses,
      minimumTransactions: PARTNER_DISCLOSURE_THRESHOLDS.minimumTransactions,
      prohibitedDimensions: prohibited[input.productId],
    },
    methodology: input.methodology,
  };
}
