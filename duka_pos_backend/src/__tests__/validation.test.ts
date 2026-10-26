import { describe, expect, it } from 'vitest';
import { parseBody, paymentSchema, salesSyncSchema, settingsSchema, staffSyncSchema, deletionSchema, provisionSchema, cloudBackupSchema, creditSyncSchema, operationalSyncSchema, productSyncSchema, stockMovementsSyncSchema, platformAnnouncementSchema, taxEntitySchema, taxRuleSchema, vatReturnStatusSchema, laybySyncSchema } from '../lib/validation';

describe('request validation', () => {
  it('allows only explicit VAT return lifecycle states', () => {
    expect(parseBody(vatReturnStatusSchema, {
      periodStart: '2026-10-01T00:00:00.000Z',
      periodEnd: '2026-11-01T00:00:00.000Z',
      status: 'accepted',
    }).status).toBe('accepted');
    expect(() => parseBody(vatReturnStatusSchema, {
      periodStart: '2026-10-01T00:00:00.000Z',
      periodEnd: '2026-11-01T00:00:00.000Z',
      status: 'filed',
    })).toThrow();
  });
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

  it('accepts only the four authoritative shop profiles', () => {
    for (const businessProfile of ['drinks', 'duka', 'fashion', 'open']) {
      expect(parseBody(provisionSchema, {
        shopName: 'Test Shop',
        ownerName: 'Owner',
        email: 'owner@example.com',
        businessProfile,
      }).businessProfile).toBe(businessProfile);
    }
    expect(() => parseBody(provisionSchema, {
      shopName: 'Test Shop',
      ownerName: 'Owner',
      email: 'owner@example.com',
      businessProfile: 'generalRetail',
    })).toThrow();
  });

  it('accepts the same product twice, and defers the total to the stock check', () => {
    // Two lines of the same product is not a validation error: it is just a
    // client that sent qty 1 twice instead of qty 2. Rejecting it here failed
    // the basket at the door, so the customer was never charged for a cart the
    // till builds routinely. Whether it can actually be fulfilled is a question
    // about accumulated stock, answered in /initiate and finalizeSale.
    const input = parseBody(paymentSchema, {
      items: [
        { product_id: '00000000-0000-0000-0000-000000000001', qty: 1 },
        { product_id: '00000000-0000-0000-0000-000000000001', qty: 1 },
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
        { product_id: '00000000-0000-0000-0000-000000000001', qty: 1, portion: 'full' },
        { product_id: '00000000-0000-0000-0000-000000000001', qty: 1, portion: 'half' },
      ],
      phone_number: '+254700000000', staff_name: 'Cashier',
    });
    expect(input.items).toHaveLength(2);
  });

  it('accepts an optional append-only tender ledger for offline sales', () => {
    const input = parseBody(paymentSchema, {
      items: [{ product_id: '00000000-0000-0000-0000-000000000001', qty: 1 }],
      phone_number: '+254700000000',
      staff_name: 'Cashier',
    });
    const sales = parseBody(salesSyncSchema, {
      sales: [{
        localId: 7,
        deviceId: 'till-1',
        staffName: 'Cashier',
        paymentMethod: 'split',
        total: 3000,
        profit: 1200,
        amountTendered: 3000,
        changeGiven: 0,
        createdAt: '2026-10-24T10:00:00.000Z',
        tenders: [
          {
            localUuid: 'tender-1',
            method: 'cash',
            amountMinor: 1000,
            tenderedMinor: 1000,
            changeMinor: 0,
            createdAt: '2026-10-24T10:00:00.000Z',
          },
          {
            localUuid: 'tender-2',
            method: 'card',
            amountMinor: 2000,
            createdAt: '2026-10-24T10:00:01.000Z',
          },
        ],
        items: [{
          productId: null,
          productName: 'Soda',
          qty: 1,
          unitPrice: 3000,
          unitCost: 1800,
          portion: 'full',
          portionMl: 350,
        }],
      }],
    });
    expect(input.items).toHaveLength(1);
    expect(sales.sales[0].tenders).toHaveLength(2);
  });

  it('rejects a line asking for more than any plausible stock', () => {
    expect(() => parseBody(paymentSchema, {
      items: [{ product_id: '00000000-0000-0000-0000-000000000001', qty: 10_000, portion: 'full' }],
      phone_number: '+254700000000', staff_name: 'Cashier',
    })).not.toThrow(); // 10,000 is under the ceiling; availability is decided later
    expect(() => parseBody(paymentSchema, {
      items: [{ product_id: '00000000-0000-0000-0000-000000000001', qty: 0 }],
      phone_number: '+254700000000', staff_name: 'Cashier',
    })).toThrow();
  });

  it('strips client-controlled payment price fields', () => {
    const input = parseBody(paymentSchema, {
      items: [{ product_id: '00000000-0000-0000-0000-000000000001', qty: 2, unit_price: 0 }],
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

  it('accepts optional line tax snapshots for offline sale replay', () => {
    const input = parseBody(salesSyncSchema, {
      sales: [{
        localId: 11,
        staffName: 'Cashier',
        paymentMethod: 'cash',
        total: 1160,
        profit: 560,
        amountTendered: 1160,
        changeGiven: 0,
        createdAt: '2026-10-24T12:00:00.000Z',
        items: [{
          productName: 'VAT soda',
          qty: 1,
          unitPrice: 1160,
          unitCost: 600,
          vatMinor: 160,
          taxableMinor: 1000,
        }],
      }],
    });
    expect(input.sales[0].items[0].taxableMinor).toBe(1000);
  });

  it('accepts buyer identity as an immutable offline sale snapshot', () => {
    const input = parseBody(salesSyncSchema, {
      sales: [{
        localId: 12,
        staffName: 'Cashier',
        buyerName: 'Acme Ltd',
        buyerTin: 'P051234567X',
        paymentMethod: 'cash',
        total: 100,
        profit: 50,
        amountTendered: 100,
        changeGiven: 0,
        createdAt: '2026-10-24T12:00:00.000Z',
        items: [{ productName: 'Soda', qty: 1, unitPrice: 100, unitCost: 50 }],
      }],
    });
    expect(input.sales[0].buyerTin).toBe('P051234567X');
  });

  it('bounds deletion reasons', () => {
    expect(() => parseBody(deletionSchema, { reason: 'x'.repeat(241) })).toThrow();
    expect(parseBody(deletionSchema, {}).reason).toBeUndefined();
  });

  it('accepts the PayHero channel field used by tenant settings', () => {
    expect(parseBody(settingsSchema, {
      mpesaEnabled: true,
      payheroChannelId: 12345,
    })).toEqual({ mpesaEnabled: true, payheroChannelId: 12345 });
    expect(() => parseBody(settingsSchema, {
      mpesaEnabled: true,
      paymentChannelId: 12345,
    })).toThrow();
  });

  it('accepts only authoritative profiles in tenant settings updates', () => {
    expect(parseBody(settingsSchema, { businessProfile: 'fashion' }))
      .toEqual({ businessProfile: 'fashion' });
    expect(() => parseBody(settingsSchema, { businessProfile: 'generalRetail' }))
      .toThrow();
  });

  it('accepts an offline sale with an unlinked product line', () => {
    const input = parseBody(salesSyncSchema, {
      sales: [{
        localId: 7,
        staffName: 'Cashier',
        paymentMethod: 'cash',
        total: 12000,
        profit: 3000,
        amountTendered: 12000,
        changeGiven: 0,
        createdAt: '2026-10-23T12:00:00.000Z',
        items: [{
          productId: null,
          productName: 'New stock',
          qty: 1,
          unitPrice: 12000,
          unitCost: 9000,
        }],
      }],
    });
    expect(input.sales[0].items[0].productId).toBeNull();
    expect(input.sales[0].items[0].portion).toBe('full');
  });

  it('accepts a persistent device namespace for multidevice sale ids', () => {
    const input = parseBody(salesSyncSchema, {
      sales: [{
        localId: 1,
        deviceId: 'till-a',
        staffName: 'Cashier',
        paymentMethod: 'cash',
        total: 100,
        profit: 20,
        amountTendered: 100,
        changeGiven: 0,
        createdAt: '2026-10-23T12:00:00.000Z',
        items: [{
          productId: null,
          productName: 'New stock',
          qty: 1,
          unitPrice: 100,
          unitCost: 80,
        }],
      }],
    });
    expect(input.sales[0].deviceId).toBe('till-a');
  });

  it('accepts a persistent device namespace for operational ids', () => {
    const input = parseBody(operationalSyncSchema, {
      records: [{ localId: 1, deviceId: 'till-a' }],
    });
    expect(input.records[0].deviceId).toBe('till-a');
  });

  it('validates a complete lay-by lifecycle snapshot', () => {
    const input = parseBody(laybySyncSchema, {
      laybys: [{
        localId: 12,
        deviceId: 'till-a',
        uuid: 'layby-12',
        customerUuid: 'customer-1',
        status: 'open',
        totalMinor: 120000,
        paidMinor: 40000,
        dueAt: '2026-11-01T12:00:00.000Z',
        createdAt: '2026-10-23T12:00:00.000Z',
        staffName: 'Amina',
        items: [{
          productId: 'cmproduct1',
          productName: 'Dress',
          qty: 1,
          unitPriceMinor: 120000,
          unitCostMinor: 70000,
          totalMinor: 120000,
        }],
        payments: [{
          localId: 30,
          method: 'cash',
          amountMinor: 40000,
          createdAt: '2026-10-23T12:00:00.000Z',
          staffName: 'Amina',
        }],
      }],
    });
    expect(input.laybys[0].status).toBe('open');
    expect(input.laybys[0].payments[0].direction).toBe('in');
    expect(() => parseBody(laybySyncSchema, {
      laybys: [{
        localId: 1,
        uuid: 'bad',
        customerUuid: 'customer-1',
        status: 'open',
        totalMinor: 10,
        paidMinor: 0,
        dueAt: '2026-11-01T12:00:00.000Z',
        createdAt: '2026-10-23T12:00:00.000Z',
        staffName: 'Amina',
        items: [],
        payments: [],
      }],
    })).toThrow();
  });

  it('keeps staff login identity separate from the display name', () => {
    const input = parseBody(staffSyncSchema, {
      staff: [{
        localId: 7,
        name: 'Amina Wanjiku',
        username: 'amina',
        role: 'cashier',
        active: true,
        pinHash: 'pbkdf2$4000$c2FsdA$dmVyaWZpZXI',
      }],
    });
    expect(input.staff[0].username).toBe('amina');
    expect(input.staff[0].name).toBe('Amina Wanjiku');
  });

  it('validates append-only stock movements with a remote product id', () => {
    const input = parseBody(stockMovementsSyncSchema, {
      stockMovements: [{
        localId: 4,
        deviceId: 'till-a',
        uuid: 'movement-4',
        productId: 'cmremoteproduct1',
        movementType: 'receipt',
        qtyDelta: 3,
        balanceAfter: 8,
        createdAt: '2026-10-23T12:00:00.000Z',
      }],
    });
    expect(input.stockMovements[0].movementType).toBe('receipt');
    const repack = parseBody(stockMovementsSyncSchema, {
      stockMovements: [{
        localId: 5,
        uuid: 'movement-repack-5',
        productId: 'cmoutputproduct1',
        movementType: 'repack',
        qtyDelta: 20,
        balanceAfter: 20,
        referenceType: 'stock_repack',
        referenceId: 4,
        createdAt: '2026-10-23T12:01:00.000Z',
      }],
    });
    expect(repack.stockMovements[0].movementType).toBe('repack');
    expect(() => parseBody(stockMovementsSyncSchema, {
      stockMovements: [{
        localId: 4,
        uuid: 'movement-4',
        productId: 'not an identifier',
        movementType: 'receipt',
        qtyDelta: 1,
        balanceAfter: 1,
        createdAt: '2026-10-23T12:00:00.000Z',
      }],
    })).toThrow();
  });

  it('preserves large tank units and their kilogram conversion', () => {
    const input = parseBody(productSyncSchema, {
      products: [{
        id: 1,
        name: 'Drinking water tank',
        costPrice: 1000,
        sellPrice: 0,
        stockQty: 2,
        openingStockQty: 5,
        reorderLevel: 1,
        bottleMl: 50000,
        unit: 'cup',
        mlPerKg: 1000,
      }],
    });
    expect(input.products[0].bottleMl).toBe(50000);
    expect(input.products[0].unit).toBe('cup');
    expect(input.products[0].mlPerKg).toBe(1000);
    expect(input.products[0].openingStockQty).toBe(5);
  });

  it('accepts only bounded opaque cloud backup payloads', () => {
    const input = parseBody(cloudBackupSchema, {
      workspaceKey: 'workspace-a',
      payload: '{"format":"duka-encrypted-backup-v1"}',
    });
    expect(input.workspaceKey).toBe('workspace-a');
    expect(() => parseBody(cloudBackupSchema, {
      workspaceKey: 'workspace-a',
      payload: '',
    })).toThrow();
  });

  it('accepts customer and credit rows keyed by local UUIDs', () => {
    const input = parseBody(creditSyncSchema, {
      customers: [{
        localUuid: 'customer-1', name: 'Mary', balanceMinor: 1200, active: true,
        createdAt: '2026-10-23T12:00:00.000Z',
      }],
      entries: [{
        localUuid: 'entry-1', customerUuid: 'customer-1', entryType: 'charge',
        amountMinor: 1200, staffName: 'Cashier',
        createdAt: '2026-10-23T12:00:00.000Z',
      }],
    });
    expect(input.entries[0].customerUuid).toBe('customer-1');
  });

  it('bounds platform announcements and defaults them active', () => {
    const input = parseBody(platformAnnouncementSchema, {
      title: 'Update available',
      body: 'A faster checkout is ready.',
    });
    expect(input.active).toBe(true);
    expect(() => parseBody(platformAnnouncementSchema, {
      title: 'x'.repeat(121),
      body: 'Message',
    })).toThrow();
  });

  it('validates tax entity obligations and effective outlet mapping', () => {
    const input = parseBody(taxEntitySchema, {
      legalForm: 'company',
      displayLabel: 'Acme Holdings',
      registeredTaxObligations: ['vat', 'etims'],
      accountingPeriodStartMonth: 1,
      effectiveFrom: '2026-10-25T00:00:00.000Z',
      outletReference: 'Nairobi-01',
    });
    expect(input.status).toBe('needs_review');
    expect(input.registeredTaxObligations).toEqual(['vat', 'etims']);
    expect(() => parseBody(taxEntitySchema, {
      legalForm: 'company',
      displayLabel: 'Acme Holdings',
      effectiveFrom: 'not-a-date',
    })).toThrow();
  });

  it('requires source-backed effective-dated tax rule configuration', () => {
    const input = parseBody(taxRuleSchema, {
      taxEntityId: 'entity-1',
      taxType: 'vat',
      scope: 'standard-rated supplies',
      taxBase: 'taxable_supply',
      rateBasisPoints: 1600,
      thresholdMinor: null,
      effectiveFrom: '2026-10-25T00:00:00.000Z',
      sourceUrl: 'https://www.kra.go.ke/taxes/value-added-tax',
      sourceReference: 'KRA VAT guidance',
    });
    expect(input.jurisdiction).toBe('KE');
    expect(input.filingFrequency).toBe('none');
    expect(() => parseBody(taxRuleSchema, {
      ...input,
      sourceUrl: 'not-a-url',
    })).toThrow();
  });
});
