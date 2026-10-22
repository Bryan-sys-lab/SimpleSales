/**
 * Email verification codes, in the only form it is safe to keep them.
 *
 * A code is a bearer credential delivered by email, so the rules are the same
 * as for any bearer credential:
 *
 *  1. IT IS NEVER STORED IN THE CLEAR. The database keeps an HMAC of the code
 *     under a per-challenge salt, so a dumped table cannot be replayed against
 *     this endpoint and a code that leaked in an email cannot be recognised by
 *     anything holding the database.
 *  2. IT IS SINGLE USE. Consuming a code consumes every outstanding code for
 *     that email, so the newest email is the only one that works and a code
 *     cannot be replayed after the shop is already verified.
 *  3. IT EXPIRES AND IT IS BOUNDED. Ten minutes of life and five attempts per
 *     code. A PIN-bound challenge that a thief cannot finish is not a lockout
 *     the shop owner pays for.
 *
 * The PIN is hashed by the same function as the code, deliberately: the local
 * 6-digit admin PIN is what binds the two halves of the flow to the same
 * person, so it is compared by the same constant-time path rather than held
 * aside as a "trusted" input.
 */

import { createHmac, randomInt, randomUUID, timingSafeEqual } from 'node:crypto';
import { normalizeEmail } from './identity';

/** Six digits: a million to one against, and short enough to read off a phone
 * lock screen without swapping apps. */
export const VERIFICATION_CODE_LENGTH = 6;

/** Long enough for a slow mail path on bad 3G; short enough that a code found
 * in a mailbox a week later is worthless. */
export const VERIFICATION_TTL_MINUTES = 10;

/** Attempts allowed against one code before it is burnt. */
export const MAX_VERIFY_ATTEMPTS = 5;

/** Codes per email per window. A shop that taps "resend" twenty times is
 * either broken or a mail bomb aimed at one of its customers. */
export const MAX_CODES_PER_WINDOW = 3;
export const CODE_REQUEST_WINDOW_MINUTES = 15;

/** Injectable so the digit selection is testable without stubbing crypto. */
export type RandomDigit = (max: number) => number;

export function generateVerificationCode(random: RandomDigit = randomInt): string {
  let code = '';
  for (let position = 0; position < VERIFICATION_CODE_LENGTH; position += 1) {
    code += random(10).toString();
  }
  return code;
}

/** A per-challenge salt. A fresh UUID, so two challenges for the same email
 * never share a hash even for the same code. */
export function newSalt(): string {
  return randomUUID();
}

/**
 * The one-way transform every secret in this flow goes through.
 *
 * `crypto.randomInt` is rejection-sampled, so the salt is uniform; the HMAC
 * key is the server's own secret, which never leaves this process. Both the
 * verification code and the admin PIN are hashed here — see the note above.
 */
export function hashCodeSecret(value: string, salt: string, secret: string): string {
  return createHmac('sha256', secret).update(`${salt}.${value}`, 'utf8').digest('hex');
}

/** Length-checked, then constant-time. A length mismatch is not a timing
 * oracle worth defending: it is reported before any comparison. */
export function hashesMatch(submitted: string, expected: string): boolean {
  const a = Buffer.from(submitted, 'utf8');
  const b = Buffer.from(expected, 'utf8');
  if (a.length !== b.length) return false;
  return timingSafeEqual(a, b);
}

export function isVerificationExpired(expiresAt: Date, now: Date): boolean {
  return expiresAt.getTime() <= now.getTime();
}

export function attemptsRemaining(attempts: number): number {
  return Math.max(0, MAX_VERIFY_ATTEMPTS - attempts);
}

/** The start of the window a new code request is counted against. */
export function codeRequestWindowStart(now: Date): Date {
  return new Date(now.getTime() - CODE_REQUEST_WINDOW_MINUTES * 60_000);
}

/**
 * The email as the UI may show it: enough to recognise, not enough to leak.
 * The full address stays in the response of nothing at all — the shop already
 * knows it, and the shop is the only party entitled to it.
 */
export function maskEmail(email: string): string {
  const normalized = normalizeEmail(email);
  const at = normalized.indexOf('@');
  if (at <= 0) return 'your email address';
  const local = normalized.slice(0, at);
  const domain = normalized.slice(at);
  const head = local.slice(0, Math.min(2, local.length));
  const dots = '*'.repeat(Math.max(1, local.length - head.length));
  return `${head}${dots}${domain}`;
}
