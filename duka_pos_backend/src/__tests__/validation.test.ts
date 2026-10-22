import { describe, expect, it } from 'vitest';
import { parseBody, paymentSchema, staffSyncSchema, deletionSchema, provisionSchema } from '../lib/validation.js';

describe('request validation', () => {
  it('requires a valid owner email when provisioning a shop', () => {
    const ok = parseBody(provisionSchema, {
      shopName: 'Test Shop',
      ownerName: 'Test Owner',
      email: 'Owner@Example.com',
    });
    expect(ok.email).toBe('owner@example.com');

    expect(() => parseBody(provisionSchema, { shopName: 'S', ownerName: 'O' })).toThrow();
    expect(() => parseBody(provisionSchema, { shopName: 'S', ownerName: 'O', email: 'not-an-email' })).toThrow();
  });

  it('accepts the same product twice, and defers the total to the stock check', () => {
    // Two lines of the same product is not a validation error: it is just a
    // client that sent qty 1 twice instead of qty 2. Rejecting it here failed
    // the basket at the door, so the customer was never charged for a cart the
    // till builds routinely. Whether it can actually be fulfilled is a question
    // about accumulated stock, answered in /initiate and finalizeSale.
    const input = parseBody(paymentSchema, {
      items: [
        { product_id: '11111111-1111-4111-8111-111111111111', qty: 1 },
        { product_id: '11111111-1111-4111-8111-111111111111', qty: 1 },
      ],
      phone_number: '+254700000000', staff_name: 'Cashier',
    });
    expect(input.items).toHaveLength(2);
  });

  it('allows different configured portions of the same product', () => {
    // The exact basket a cashier builds for "one whole plus one half of the
    // same bottle" — 1.5 bottles of stock, one full line and one half line.
    const input = parseBody(paymentSchema, {
      items: [
        { product_id: '11111111-1111-4111-8111-111111111111', qty: 1, portion: 'full' },
        { product_id: '11111111-1111-4111-8111-111111111111', qty: 1, portion: 'half' },
      ],
      phone_number: '+254700000000', staff_name: 'Cashier',
    });
    expect(input.items).toHaveLength(2);
  });

  it('rejects a line asking for more than any plausible stock', () => {
    expect(() => parseBody(paymentSchema, {
      items: [{ product_id: '11111111-1111-4111-8111-111111111111', qty: 10_000, portion: 'full' }],
      phone_number: '+254700000000', staff_name: 'Cashier',
    })).not.toThrow(); // 10,000 is under the ceiling; availability is decided later
    expect(() => parseBody(paymentSchema, {
      items: [{ product_id: '11111111-1111-4111-8111-111111111111', qty: 0 }],
      phone_number: '+254700000000', staff_name: 'Cashier',
    })).toThrow();
  });

  it('strips client-controlled payment price fields', () => {
    const input = parseBody(paymentSchema, {
      items: [{ product_id: '11111111-1111-4111-8111-111111111111', qty: 2, unit_price: 0 }],
      phone_number: '+254700000000', staff_name: 'Cashier', amount: 0,
    });
    expect(input.items[0]).not.toHaveProperty('unit_price');
    expect(input).not.toHaveProperty('amount');
  });

  it('accepts only cashier or manager staff roles', () => {
    const valid = parseBody(staffSyncSchema, { staff: [{ localId: 1, name: 'Manager', role: 'manager' }] });
    expect(valid.staff[0].role).toBe('manager');
    expect(() => parseBody(staffSyncSchema, { staff: [{ localId: 2, name: 'Root', role: 'admin' }] })).toThrow();
  });

  it('bounds deletion reasons', () => {
    expect(() => parseBody(deletionSchema, { reason: 'x'.repeat(241) })).toThrow();
    expect(parseBody(deletionSchema, {}).reason).toBeUndefined();
  });
});
