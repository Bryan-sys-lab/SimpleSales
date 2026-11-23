import { describe, expect, it } from 'vitest';
import {
  adminPackagePermissions,
  isAdminPermission,
  normalizeAdminPackages,
} from '../lib/admin_access_catalog';

describe('admin access packages', () => {
  it('combines package scopes without duplicates', () => {
    expect(adminPackagePermissions(['sales', 'finance'])).toEqual([
      'analytics:read',
      'commercial:read',
      'configuration:read',
      'membership:read',
      'membership:manage',
      'tenants:read',
    ]);
  });

  it('normalizes valid packages and falls back to legacy departments', () => {
    expect(normalizeAdminPackages(['sales', 'sales', 'unknown'], 'Finance'))
      .toEqual(['sales']);
    expect(normalizeAdminPackages([], 'Operations')).toEqual(['operations']);
    expect(normalizeAdminPackages([], 'Unknown')).toEqual(['custom']);
  });

  it('does not recognize arbitrary permission scopes', () => {
    expect(isAdminPermission('membership:manage')).toBe(true);
    expect(isAdminPermission('system:root')).toBe(false);
  });
});
