import { describe, expect, it } from 'vitest';
import {
  adminPackagePermissions,
  effectiveAdminPermissions,
  isAdminPermission,
  normalizeAdminPackages,
} from '../lib/admin_access_catalog';

describe('admin access packages', () => {
  it('combines package scopes without duplicates', () => {
    expect(adminPackagePermissions(['sales', 'finance'])).toEqual([
      'analytics:read',
      'commercial:read',
      'configuration:read',
      'billing:manage',
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
    expect(isAdminPermission('billing:manage')).toBe(true);
    expect(isAdminPermission('system:root')).toBe(false);
  });

  it('applies new package scopes to existing accounts without removing extra scopes', () => {
    expect(effectiveAdminPermissions(['finance'], ['configuration:read', 'users:read']))
      .toEqual(['analytics:read', 'commercial:read', 'configuration:read', 'billing:manage', 'users:read']);
    expect(adminPackagePermissions(['marketing'])).toContain('billing:manage');
  });
});
