import { describe, expect, it } from 'vitest';
import { isVerifiedEmailMatch, normalizeEmail } from '../lib/identity.js';

describe('authoritative online identity', () => {
  it('normalizes case and whitespace', () => {
    expect(normalizeEmail('  Owner@Example.COM ')).toBe('owner@example.com');
    expect(normalizeEmail(undefined)).toBe('');
    expect(normalizeEmail(42)).toBe('');
  });

  it('accepts a matching verified token email', () => {
    expect(isVerifiedEmailMatch(
      { sub: 'u1', email: 'owner@example.com', email_verified: true },
      'owner@example.com',
    )).toBe(true);
  });

  it('is case-insensitive and whitespace-tolerant', () => {
    expect(isVerifiedEmailMatch(
      { sub: 'u1', email: 'Owner@Example.com' },
      ' owner@example.com ',
    )).toBe(true);
  });

  it('rejects a token email that does not match the requested email', () => {
    expect(isVerifiedEmailMatch(
      { sub: 'u1', email: 'attacker@example.com', email_verified: true },
      'owner@example.com',
    )).toBe(false);
  });

  it('rejects an explicitly unverified email', () => {
    expect(isVerifiedEmailMatch(
      { sub: 'u1', email: 'owner@example.com', email_verified: false },
      'owner@example.com',
    )).toBe(false);
  });

  it('rejects when the token carries no email', () => {
    expect(isVerifiedEmailMatch({ sub: 'u1' }, 'owner@example.com')).toBe(false);
    expect(isVerifiedEmailMatch({ sub: 'u1', email: '   ' }, 'owner@example.com')).toBe(false);
  });

  it('rejects when no claims are present', () => {
    expect(isVerifiedEmailMatch(undefined, 'owner@example.com')).toBe(false);
  });
});
