import { describe, expect, it } from 'vitest';
import { adminPermissionFor } from '../middleware/auth';

describe('admin billing permission scopes', () => {
  it('allows billing managers to set terms and manage vouchers without provider configuration access', () => {
    expect(adminPermissionFor('PATCH', '/admin/billing/subscriptions/tenant-1')).toBe('billing:manage');
    expect(adminPermissionFor('POST', '/admin/billing/vouchers')).toBe('billing:manage');
    expect(adminPermissionFor('POST', '/admin/billing/vouchers/voucher-1/revoke')).toBe('billing:manage');
    expect(adminPermissionFor('GET', '/admin/billing/shop-options')).toBe('configuration:read');
    expect(adminPermissionFor('PATCH', '/admin/billing/provider')).toBe('configuration:manage');
  });
});
