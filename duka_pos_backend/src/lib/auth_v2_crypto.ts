import { pbkdf2 as pbkdf2Callback } from 'node:crypto';
import { promisify } from 'node:util';

const pbkdf2Async = promisify(pbkdf2Callback);

// Pure constant-time compare keeps Workers runtime compatibility (no node:crypto Buffer dependency).
function timingSafeEqualBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

export const STAFF_PIN_V2_ALGORITHM = 'pbkdf2';
export const STAFF_PIN_V2_VERSION = 'v2';
export const STAFF_PIN_V2_PRF = 'sha256';
// Cloudflare Workers WebCrypto/node:crypto PBKDF2 currently caps iterations at 100000.
// V2 uses the platform maximum; keep the versioned format so iterations can increase when supported.
export const STAFF_PIN_V2_ITERATIONS = 100_000;
export const STAFF_PIN_V2_SALT_BYTES = 16;
export const STAFF_PIN_V2_KEY_BYTES = 32;
export const STAFF_PIN_MIN_ITERATIONS = 100_000;
export const STAFF_PIN_MAX_ITERATIONS = 2_000_000;

export type StaffPinHashFormat = 'legacy-pbkdf2' | 'v2';

export type ParsedStaffPinHash = {
  format: StaffPinHashFormat;
  algorithm: 'pbkdf2';
  version: 'v1' | 'v2';
  prf: 'sha256';
  iterations: number;
  salt: Uint8Array;
  key: Uint8Array;
};

export function isSixDigitPin(value: unknown): value is string {
  return typeof value === 'string' && /^\d{6}$/.test(value);
}

export function isStaffPinV2Input(value: unknown): value is string {
  return isSixDigitPin(value);
}

export function encodeBase64Url(value: Uint8Array): string {
  let binary = '';
  for (const byte of value) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

export function decodeBase64Url(value: string): Uint8Array {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/').replace(/=+$/g, '');
  if (!/^[A-Za-z0-9+/]*$/.test(base64)) {
    throw new Error('Invalid base64url value');
  }
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4);
  const decoded = atob(padded);
  return Uint8Array.from(decoded, (character) => character.charCodeAt(0));
}

export function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  return timingSafeEqualBytes(a, b);
}

export async function deriveStaffPinKey(
  pin: string,
  salt: Uint8Array,
  iterations: number,
  keyBytes = STAFF_PIN_V2_KEY_BYTES,
): Promise<Uint8Array> {
  // Workers WebCrypto PBKDF2 currently rejects iteration counts above 100000;
  // use node:crypto pbkdf2 (nodejs_compat) for V2's higher iteration target.
  const derived = await pbkdf2Async(pin, Buffer.from(salt), iterations, keyBytes, 'sha256');
  return new Uint8Array(derived);
}

export function serializeStaffPinHashV2(params: {
  iterations: number;
  salt: Uint8Array;
  key: Uint8Array;
}): string {
  return [
    STAFF_PIN_V2_ALGORITHM,
    STAFF_PIN_V2_VERSION,
    STAFF_PIN_V2_PRF,
    String(params.iterations),
    encodeBase64Url(params.salt),
    encodeBase64Url(params.key),
  ].join('$');
}

export function parseStaffPinHash(stored: string | null | undefined): ParsedStaffPinHash | null {
  if (!stored || typeof stored !== 'string') return null;
  const parts = stored.split('$');
  try {
    if (parts.length === 4 && parts[0] === 'pbkdf2') {
      // Legacy/current format: pbkdf2$<iterations>$<salt>$<key>
      const iterations = Number.parseInt(parts[1], 10);
      if (!Number.isSafeInteger(iterations) || iterations < 1 || iterations > STAFF_PIN_MAX_ITERATIONS) return null;
      const salt = decodeBase64Url(parts[2]);
      const key = decodeBase64Url(parts[3]);
      if (salt.length < 1 || key.length < 16 || key.length > 64) return null;
      return { format: 'legacy-pbkdf2', algorithm: 'pbkdf2', version: 'v1', prf: 'sha256', iterations, salt, key };
    }
    if (parts.length === 6 && parts[0] === 'pbkdf2' && parts[1] === 'v2' && parts[2] === 'sha256') {
      const iterations = Number.parseInt(parts[3], 10);
      if (!Number.isSafeInteger(iterations) || iterations < STAFF_PIN_MIN_ITERATIONS || iterations > STAFF_PIN_MAX_ITERATIONS) return null;
      const salt = decodeBase64Url(parts[4]);
      const key = decodeBase64Url(parts[5]);
      if (salt.length !== STAFF_PIN_V2_SALT_BYTES || key.length !== STAFF_PIN_V2_KEY_BYTES) return null;
      return { format: 'v2', algorithm: 'pbkdf2', version: 'v2', prf: 'sha256', iterations, salt, key };
    }
  } catch {
    return null;
  }
  return null;
}

export async function hashStaffPinV2(pin: string, iterations = STAFF_PIN_V2_ITERATIONS): Promise<string> {
  if (!isSixDigitPin(pin)) {
    throw new Error('Staff PIN must be exactly 6 digits');
  }
  if (!Number.isSafeInteger(iterations) || iterations < STAFF_PIN_MIN_ITERATIONS || iterations > STAFF_PIN_MAX_ITERATIONS) {
    throw new Error('Unsupported staff PIN iteration count');
  }
  const salt = globalThis.crypto.getRandomValues(new Uint8Array(STAFF_PIN_V2_SALT_BYTES));
  const key = await deriveStaffPinKey(pin, salt, iterations, STAFF_PIN_V2_KEY_BYTES);
  return serializeStaffPinHashV2({ iterations, salt, key });
}

export function legacyStaffPinHashesAllowed(): boolean {
  return process.env.AUTH_V2_ALLOW_LEGACY_PIN_HASHES !== 'false';
}

export async function verifyStaffPinHash(pin: string, stored: string | null | undefined): Promise<boolean> {
  if (typeof pin !== 'string' || pin.length === 0) return false;
  const parsed = parseStaffPinHash(stored);
  if (!parsed) return false;
  if (!legacyStaffPinHashesAllowed() && parsed.format !== 'v2') return false;
  try {
    const actual = await deriveStaffPinKey(pin, parsed.salt, parsed.iterations, parsed.key.length);
    return constantTimeEqual(actual, parsed.key);
  } catch {
    return false;
  }
}

export function staffPinNeedsRehash(stored: string | null | undefined): boolean {
  const parsed = parseStaffPinHash(stored);
  if (!parsed) return false;
  return parsed.format !== 'v2' || parsed.iterations !== STAFF_PIN_V2_ITERATIONS;
}

export function describeStaffPinHash(stored: string | null | undefined): { format: string; version: string; iterations: number | null } {
  const parsed = parseStaffPinHash(stored);
  if (!parsed) return { format: 'invalid', version: 'unknown', iterations: null };
  return { format: parsed.format, version: parsed.version, iterations: parsed.iterations };
}
