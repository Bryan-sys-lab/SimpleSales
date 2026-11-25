import { describe, expect, it } from 'vitest';
import {
  billingIntervalForMonths,
  billingIntervalMonths,
  calculateSubscriptionQuote,
  effectiveSubscriptionDiscountPercent,
} from '../lib/subscription_pricing';

describe('subscription pricing', () => {
  it('maps admin billing periods to server-controlled charge terms', () => {
    expect(billingIntervalMonths('quarterly')).toBe(3);
    expect(billingIntervalMonths('semiannual')).toBe(6);
    expect(billingIntervalForMonths(12)).toBe('annual');
    expect(billingIntervalForMonths(2)).toBeNull();
    expect(() => billingIntervalMonths('unknown')).toThrow(RangeError);
  });

  it('applies the administrator discount to the full selected term', () => {
    expect(calculateSubscriptionQuote(10_001, 3, 10)).toEqual({
      baseAmountMinor: 30_003,
      discountAmountMinor: 3_000,
      amountMinor: 27_000,
    });
  });

  it('rounds the charged total to whole shillings without changing the nominal discount', () => {
    expect(calculateSubscriptionQuote(10_050, 1, 0)).toEqual({
      baseAmountMinor: 10_050,
      discountAmountMinor: 0,
      amountMinor: 10_100,
    });
    expect(calculateSubscriptionQuote(10_000, 1, 99).amountMinor).toBe(100);
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
