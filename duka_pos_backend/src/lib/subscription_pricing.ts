const BILLING_DURATIONS = new Set([1, 3, 6, 12]);

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
  const amountMinor = Math.round(baseAmountMinor * (100 - discountPercent) / 100);
  if (amountMinor < 1) {
    throw new RangeError('Discounted subscription total must be at least one minor currency unit');
  }
  return {
    baseAmountMinor,
    discountAmountMinor: baseAmountMinor - amountMinor,
    amountMinor,
  };
}
