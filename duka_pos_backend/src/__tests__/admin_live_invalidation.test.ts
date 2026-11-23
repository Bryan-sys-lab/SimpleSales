import { describe, expect, it } from 'vitest';
import { adminLiveInvalidationFor } from '../services/admin_live_invalidation';

describe('admin live invalidation mapping', () => {
  it('publishes scoped invalidations for billing and membership writes without changing their routes', () => {
    const billing = adminLiveInvalidationFor('PATCH', '/api/admin/billing/provider');
    const membership = adminLiveInvalidationFor('POST', '/api/admin/membership/requests/request-1/offers');

    expect(billing?.resources).toEqual(['billing', 'financials', 'audit']);
    expect(billing?.requiredPermissions).toEqual(['configuration:read', 'analytics:read', 'audit:read']);
    expect(membership?.resources).toEqual(['membership', 'audit']);
    expect(membership?.requiredPermissions).toEqual(['membership:read', 'audit:read']);
  });

  it('does not publish for reads, unrelated routes, or explicit event broadcasts', () => {
    expect(adminLiveInvalidationFor('GET', '/api/admin/billing/provider')).toBeNull();
    expect(adminLiveInvalidationFor('POST', '/api/unmapped/write')).toBeNull();
    expect(adminLiveInvalidationFor('POST', '/api/telemetry/events')).toBeNull();
  });

  it('refreshes user and sales views after app profile and evidence writes', () => {
    expect(adminLiveInvalidationFor('POST', '/api/profile/photo/confirm')?.resources).toEqual([
      'users', 'tenants',
    ]);
    expect(adminLiveInvalidationFor('POST', '/api/evidence/sync')?.resources).toEqual(['sales']);
    expect(adminLiveInvalidationFor('POST', '/api/sale-evidence/confirm')?.resources).toEqual(['sales']);
  });
});
