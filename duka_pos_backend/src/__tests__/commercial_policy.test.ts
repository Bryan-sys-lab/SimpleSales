import { describe, expect, it } from 'vitest';
import { COMMERCIAL_POLICY } from '../lib/commercial_policy';

describe('commercial intelligence policy boundary', () => {
  it('is disclosed as a separate disabled purpose with an explicit allowlist', () => {
    expect(COMMERCIAL_POLICY.policyId).toBe('commercial-intelligence');
    expect(COMMERCIAL_POLICY.collectionEnabled).toBe(false);
    expect(COMMERCIAL_POLICY.status).toBe('disabled_pending_approval');
    expect(COMMERCIAL_POLICY.allowlist).toContain('business_profile');
    expect(COMMERCIAL_POLICY.allowlist).toContain('gross_revenue_minor_aggregate');
    expect(COMMERCIAL_POLICY.allowlist).not.toContain('customer_name');
  });

  it('prohibits direct identifiers and source-level records', () => {
    const allowlist = new Set(COMMERCIAL_POLICY.allowlist);
    for (const field of COMMERCIAL_POLICY.prohibited) {
      expect(allowlist.has(field)).toBe(false);
    }
  });
});
