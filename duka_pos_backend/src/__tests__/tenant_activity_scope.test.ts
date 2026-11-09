import { describe, expect, it } from 'vitest';
import { activityTenantScope } from '../lib/activity_scope';

describe('cross-shop activity authorization scope', () => {
  it('returns every authorized shop when no narrowing filter is supplied', () => {
    expect(activityTenantScope(['drinks', 'duka', 'fashion', 'open'])).toEqual([
      'drinks',
      'duka',
      'fashion',
      'open',
    ]);
  });

  it('allows a requested shop only as a narrowing filter', () => {
    expect(activityTenantScope(['drinks', 'duka'], 'duka')).toEqual(['duka']);
  });

  it('denies a shop outside the resolved account scope', () => {
    expect(activityTenantScope(['drinks', 'duka'], 'fashion')).toBeNull();
  });
});
