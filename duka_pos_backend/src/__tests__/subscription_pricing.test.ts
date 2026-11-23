import { describe, expect, it } from 'vitest';
import {
  calculateSubscriptionQuote,
  effectiveSubscriptionDiscountPercent,
} from '../lib/subscription_pricing';

describe('subscription pricing', () => {
  it('applies the administrator discount to the full selected term', () => {
    expect(calculateSubscriptionQuote(10_001, 3, 10)).toEqual({
      baseAmountMinor: 30_003,
      discountAmountMinor: 3_000,
      amountMinor: 27_003,
    });
  });

  it('rejects unsupported billing terms and discounts', () => {
    expect(() => calculateSubscriptionQuote(10_000, 2, 10)).toThrow(RangeError);
    expect(() => calculateSubscriptionQuote(10_000, 12, 100)).toThrow(RangeError);
  });

  it('uses the larger of a voucher and negotiated discount without stacking', () => {
    expect(effectiveSubscriptionDiscountPercent(10, 'discount', 25)).toBe(25);
    expect(effectiveSubscriptionDiscountPercent(30, 'discount', 25)).toBe(30);
    expect(effectiveSubscriptionDiscountPercent(10, 'access', 25)).toBe(10);
  });
});
