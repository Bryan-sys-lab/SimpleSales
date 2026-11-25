const BILLING_DURATIONS = new Set([1, 3, 6, 12]);

export function billingIntervalMonths(interval: string): number {
  switch (interval) {
    case 'monthly':
      return 1;
    case 'quarterly':
      return 3;
    case 'semiannual':
      return 6;
    case 'annual':
      return 12;
    default:
      throw new RangeError(`Unsupported subscription billing interval: ${interval}`);
  }
}

export function billingIntervalForMonths(months: number): string | null {
  switch (months) {
    case 1:
      return 'monthly';
    case 3:
      return 'quarterly';
    case 6:
      return 'semiannual';
    case 12:
      return 'annual';
    default:
      return null;
  }
}

export function effectiveSubscriptionDiscountPercent(
  negotiatedPercent: number | null | undefined,
  voucherType: string | null | undefined,
  voucherPercent: number | null | undefined,
): number {
  const negotiated = negotiatedPercent ?? 0;
  const voucher = voucherPercent ?? 0;
  if (!Number.isInteger(negotiated) || negotiated < 0 || negotiated > 99) {
    throw new RangeError('Negotiated subscription discount must be between 0 and 99 percent');
  }
  if (!Number.isInteger(voucher) || voucher < 0 || voucher > 99) {
    throw new RangeError('Voucher discount must be between 0 and 99 percent');
  }
  return voucherType === 'discount' ? Math.max(negotiated, voucher) : negotiated;
}

export function calculateSubscriptionQuote(
  priceMinor: number,
  durationMonths: number,
  discountPercent: number,
): {
  baseAmountMinor: number;
  discountAmountMinor: number;
  amountMinor: number;
} {
  if (!Number.isSafeInteger(priceMinor) || priceMinor <= 0) {
    throw new RangeError('Subscription price must be a positive safe integer');
  }
  if (!BILLING_DURATIONS.has(durationMonths)) {
    throw new RangeError('Subscription duration must be 1, 3, 6, or 12 months');
  }
  if (!Number.isInteger(discountPercent) || discountPercent < 0 || discountPercent > 99) {
    throw new RangeError('Subscription discount must be between 0 and 99 percent');
  }

  const baseAmountMinor = priceMinor * durationMonths;
  if (!Number.isSafeInteger(baseAmountMinor)) {
    throw new RangeError('Subscription quote is too large to charge safely');
  }
  const discountedAmountMinor = Math.round(baseAmountMinor * (100 - discountPercent) / 100);
  const amountMinor = Math.round(discountedAmountMinor / 100) * 100;
  if (amountMinor < 100) {
    throw new RangeError('Discounted subscription total must be at least one whole currency unit');
  }
  return {
    baseAmountMinor,
    discountAmountMinor: baseAmountMinor - discountedAmountMinor,
    amountMinor,
  };
}
