import { describe, expect, it } from 'vitest';
import { calculateSubscriptionQuote } from '../lib/subscription_pricing';

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
});
