export const DATA_DICTIONARY_VERSION = 'duka-pos-data-dictionary-v2';

export const CANONICAL_QUALITY_STATES = [
  'valid',
  'mapped',
  'unmapped',
  'missing',
  'unknown',
  'not_applicable',
  'unverified',
  'stale',
  'rejected',
] as const;

export type CanonicalQualityState = (typeof CANONICAL_QUALITY_STATES)[number];

export type CanonicalMetricDefinition = {
  key: string;
  formula: string;
  currency?: 'KES';
  unit: 'minor_units' | 'count' | 'quantity' | 'ratio' | 'days';
  source: string;
  exclusion: string;
  qualityState: CanonicalQualityState;
};

export const CANONICAL_METRIC_DEFINITIONS: readonly CanonicalMetricDefinition[] = [
  { key: 'completed_sale_count', formula: 'COUNT(distinct completed eligible sale headers)', unit: 'count', source: 'sales', exclusion: 'void/test/failed/incomplete', qualityState: 'valid' },
  { key: 'gross_sales_minor', formula: 'SUM(persisted line extended selling value before discounts/refunds)', currency: 'KES', unit: 'minor_units', source: 'sale_items', exclusion: 'void/refunded/failed; refunds kept separate', qualityState: 'valid' },
  { key: 'discount_minor', formula: 'SUM(line/order discount snapshots net of reversals)', currency: 'KES', unit: 'minor_units', source: 'sales; sale_items', exclusion: 'do not count a discount twice', qualityState: 'valid' },
  { key: 'refund_minor', formula: 'SUM(linked reversal value)', currency: 'KES', unit: 'minor_units', source: 'returns/refunds', exclusion: 'unlinked reversals stay unverified', qualityState: 'valid' },
  { key: 'net_sales_ex_tax_minor', formula: 'gross_sales - discounts - refunds - excluded tax', currency: 'KES', unit: 'minor_units', source: 'persisted sale and tax snapshots', exclusion: 'never derive from current tax rules', qualityState: 'valid' },
  { key: 'tax_collected_minor', formula: 'SUM(persisted sale-time tax snapshot)', currency: 'KES', unit: 'minor_units', source: 'sales; sale_items', exclusion: 'not revenue', qualityState: 'valid' },
  { key: 'confirmed_payment_minor', formula: 'SUM(confirmed payment records)', currency: 'KES', unit: 'minor_units', source: 'sale_payments', exclusion: 'pending/unverified and credit excluded from cash', qualityState: 'valid' },
  { key: 'receivable_minor', formula: 'SUM(confirmed credit-sale receivable entries)', currency: 'KES', unit: 'minor_units', source: 'credit_ledger', exclusion: 'never commercial output without separate lawful purpose', qualityState: 'valid' },
  { key: 'cash_received_minor', formula: 'SUM(confirmed tender/cash-in)', currency: 'KES', unit: 'minor_units', source: 'sale_payments', exclusion: 'credit and pending payments excluded', qualityState: 'valid' },
  { key: 'unit_volume', formula: 'SUM(valid sale quantities converted to the declared base unit)', unit: 'quantity', source: 'sale_items; product unit mapping', exclusion: 'never combine kg/litre/each/pair/service-hour', qualityState: 'mapped' },
  { key: 'stock_tracking_coverage', formula: 'tracked active physical goods / eligible active physical goods', unit: 'ratio', source: 'products', exclusion: 'services, fees and unknown item kinds excluded', qualityState: 'valid' },
  { key: 'observed_availability', formula: 'valid positive-or-zero tracked observations / valid observed time', unit: 'ratio', source: 'stock snapshots/movements', exclusion: 'missing snapshots are unknown', qualityState: 'valid' },
  { key: 'stockout_rate', formula: 'valid observed stockout time / valid tracked observation time', unit: 'ratio', source: 'stock snapshots/movements', exclusion: 'services, fees, untracked and stale goods excluded', qualityState: 'valid' },
  { key: 'procurement_digitisation', formula: 'POs with line items and linked received quantity / eligible POs', unit: 'ratio', source: 'purchase_orders; stock_receipts', exclusion: 'cancelled/open POs not completed fill denominator', qualityState: 'valid' },
  { key: 'po_receipt_lead_time_days', formula: 'valid actual_received_at_utc - linked ordered_at_utc', unit: 'days', source: 'purchase_orders; stock_receipts', exclusion: 'only linked valid receipt records', qualityState: 'valid' },
  { key: 'po_fill_rate', formula: 'SUM(matched received quantity) / SUM(matched ordered quantity)', unit: 'ratio', source: 'purchase_order_lines; stock_receipt_items', exclusion: 'cancelled/open order lines excluded from complete denominator', qualityState: 'valid' },
  { key: 'business_profile_completeness', formula: 'applicable populated or explicitly declined fields / applicable fields', unit: 'ratio', source: 'business_context', exclusion: 'prefer-not-to-say is complete, not missing', qualityState: 'valid' },
  { key: 'sales_record_completeness', formula: 'completed eligible sales with at least one valid sale line / completed eligible sales', unit: 'ratio', source: 'sales; sale_items', exclusion: 'void/test/failed sales excluded', qualityState: 'valid' },
] as const;

export type CanonicalMetricFixtureInput = {
  periodStartUtc: string;
  periodEndUtc: string;
  grossSalesMinor: number;
  discountMinor: number;
  refundMinor: number;
  taxMinor: number;
  confirmedPaymentMinor: number;
  receivableMinor: number;
  cashReceivedMinor: number;
  validTrackedObservation: number;
  validStockoutObservation: number;
  orderedQuantity: number | null;
  receivedQuantity: number | null;
  applicableProfileFields: number;
  populatedOrDeclinedProfileFields: number;
  completedSales: number;
  completedSalesWithValidLines: number;
  unitVolumes: Array<{ quantity: number; unit: 'kg' | 'litre' | 'each' | 'pair' | 'service_hour' }>;
};

export type CanonicalMetricFixtureResult = {
  dictionaryVersion: typeof DATA_DICTIONARY_VERSION;
  period: { startUtc: string; endUtc: string };
  grossSalesMinor: number;
  discountMinor: number;
  refundMinor: number;
  netSalesExTaxMinor: number;
  taxMinor: number;
  confirmedPaymentMinor: number;
  receivableMinor: number;
  cashReceivedMinor: number;
  unitVolumes: Partial<Record<CanonicalMetricFixtureInput['unitVolumes'][number]['unit'], number>>;
  stockoutRate: number | null;
  poFillRate: number | null;
  businessProfileCompleteness: number | null;
  salesRecordCompleteness: number | null;
  qualityStates: Record<string, CanonicalQualityState>;
};

export function calculateCanonicalMetricFixture(
  input: CanonicalMetricFixtureInput,
): CanonicalMetricFixtureResult {
  const nonnegative = (value: number) => Number.isFinite(value) && value >= 0;
  if (!nonnegative(input.grossSalesMinor)
    || !nonnegative(input.discountMinor)
    || !nonnegative(input.refundMinor)
    || !nonnegative(input.taxMinor)
    || !nonnegative(input.confirmedPaymentMinor)
    || !nonnegative(input.receivableMinor)
    || !nonnegative(input.cashReceivedMinor)) {
    throw new Error('Canonical money and count fixtures must be finite and non-negative');
  }
  if (input.periodStartUtc >= input.periodEndUtc) throw new Error('Invalid canonical metric period');

  const unitVolumes: CanonicalMetricFixtureResult['unitVolumes'] = {};
  for (const volume of input.unitVolumes) {
    if (!nonnegative(volume.quantity)) throw new Error('Unit volumes must be finite and non-negative');
    unitVolumes[volume.unit] = (unitVolumes[volume.unit] ?? 0) + volume.quantity;
  }

  const stockoutRate = input.validTrackedObservation === 0
    ? null
    : input.validStockoutObservation / input.validTrackedObservation;
  const poFillRate = input.orderedQuantity === null || input.orderedQuantity <= 0
    ? null
    : input.receivedQuantity === null
      ? null
      : input.receivedQuantity / input.orderedQuantity;
  const businessProfileCompleteness = input.applicableProfileFields === 0
    ? null
    : input.populatedOrDeclinedProfileFields / input.applicableProfileFields;
  const salesRecordCompleteness = input.completedSales === 0
    ? null
    : input.completedSalesWithValidLines / input.completedSales;

  return {
    dictionaryVersion: DATA_DICTIONARY_VERSION,
    period: { startUtc: input.periodStartUtc, endUtc: input.periodEndUtc },
    grossSalesMinor: input.grossSalesMinor,
    discountMinor: input.discountMinor,
    refundMinor: input.refundMinor,
    netSalesExTaxMinor: input.grossSalesMinor - input.discountMinor - input.refundMinor - input.taxMinor,
    taxMinor: input.taxMinor,
    confirmedPaymentMinor: input.confirmedPaymentMinor,
    receivableMinor: input.receivableMinor,
    cashReceivedMinor: input.cashReceivedMinor,
    unitVolumes,
    stockoutRate,
    poFillRate,
    businessProfileCompleteness,
    salesRecordCompleteness,
    qualityStates: {
      missingCost: 'missing',
      stockSnapshot: input.validTrackedObservation === 0 ? 'unknown' : 'valid',
      purchaseReceiptLink: poFillRate === null ? 'missing' : 'valid',
      serviceInventory: 'not_applicable',
    },
  };
}
