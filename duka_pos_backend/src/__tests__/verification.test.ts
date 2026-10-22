import { describe, expect, it } from 'vitest';
import {
  CODE_REQUEST_WINDOW_MINUTES,
  MAX_VERIFY_ATTEMPTS,
  generateVerificationCode,
  hashCodeSecret,
  hashesMatch,
  isVerificationExpired,
  maskEmail,
  newSalt,
  attemptsRemaining,
  codeRequestWindowStart,
} from '../lib/verification';

const SECRET = 'server-side-secret-that-never-leaves-this-process';

describe('verification code generation', () => {
  it('produces exactly six digits', () => {
    const code = generateVerificationCode(() => 7);
    expect(code).toBe('777777');
    expect(code).toHaveLength(6);
    expect(/^\d{6}$/.test(code)).toBe(true);
  });

  it('never produces a value outside the digits', () => {
    // A count above ten would mean the caller is passing a biased generator.
    let calls = 0;
    generateVerificationCode((max) => {
      expect(max).toBe(10);
      calls += 1;
      return max - 1;
    });
    expect(calls).toBe(6);
  });

  it('draws every digit position, so a code is not one digit repeated by accident', () => {
    const digits = [0, 1, 2, 3, 4, 5];
    let index = 0;
    const code = generateVerificationCode(() => digits[index++]);
    expect(code).toBe('012345');
  });
});

describe('code hashing', () => {
  it('is stable for the same code, salt and secret', () => {
    expect(hashCodeSecret('123456', 'salt', SECRET)).toBe(hashCodeSecret('123456', 'salt', SECRET));
  });

  it('does not collide across codes', () => {
    expect(hashCodeSecret('123456', 'salt', SECRET)).not.toBe(hashCodeSecret('123457', 'salt', SECRET));
  });

  it('does not collide across salts, so a dumped table cannot be replayed', () => {
    expect(hashCodeSecret('123456', 'salt-a', SECRET)).not.toBe(hashCodeSecret('123456', 'salt-b', SECRET));
  });

  it('depends on the server secret', () => {
    expect(hashCodeSecret('123456', 'salt', 'secret-a')).not.toBe(hashCodeSecret('123456', 'salt', 'secret-b'));
  });

  it('never contains the code itself', () => {
    expect(hashCodeSecret('123456', 'salt', SECRET)).not.toContain('123456');
  });

  it('gives every challenge a distinct salt', () => {
    expect(newSalt()).not.toBe(newSalt());
  });

  it('matches only the identical value, in constant time', () => {
    const hash = hashCodeSecret('123456', 'salt', SECRET);
    expect(hashesMatch(hashCodeSecret('123456', 'salt', SECRET), hash)).toBe(true);
    expect(hashesMatch(hashCodeSecret('123457', 'salt', SECRET), hash)).toBe(false);
    // A length mismatch is reported, not crashed on.
    expect(hashesMatch('short', hash)).toBe(false);
  });
});

describe('expiry and attempts', () => {
  it('expires at exactly the expiry instant', () => {
    const expiry = new Date('2026-10-10T12:00:00.000Z');
    expect(isVerificationExpired(expiry, new Date('2026-10-10T11:59:59.999Z'))).toBe(false);
    expect(isVerificationExpired(expiry, new Date('2026-10-10T12:00:00.000Z'))).toBe(true);
  });

  it('counts down and never goes negative', () => {
    expect(attemptsRemaining(0)).toBe(MAX_VERIFY_ATTEMPTS);
    expect(attemptsRemaining(MAX_VERIFY_ATTEMPTS - 1)).toBe(1);
    expect(attemptsRemaining(MAX_VERIFY_ATTEMPTS)).toBe(0);
    expect(attemptsRemaining(MAX_VERIFY_ATTEMPTS + 4)).toBe(0);
  });

  it('opens the code-request window fifteen minutes back', () => {
    const now = new Date('2026-10-10T12:00:00.000Z');
    const windowStart = codeRequestWindowStart(now);
    expect(windowStart.getTime()).toBe(now.getTime() - CODE_REQUEST_WINDOW_MINUTES * 60_000);
  });
});

describe('email masking', () => {
  it('shows enough to recognise and no more', () => {
    expect(maskEmail('owner@example.com')).toBe('ow***@example.com');
  });

  it('handles a one-character local part and case', () => {
    expect(maskEmail('a@example.com')).toBe('a*@example.com');
    expect(maskEmail('  Owner@Example.COM ')).toBe('ow***@example.com');
  });

  it('has nothing to leak when there is no address', () => {
    expect(maskEmail('')).toBe('your email address');
    expect(maskEmail('not-an-email')).toBe('your email address');
  });
});
