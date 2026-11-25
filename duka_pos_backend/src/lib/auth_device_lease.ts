import { createHmac } from 'node:crypto';

const DEFAULT_OFFLINE_LEASE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function timingSafeEqualBytes(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) diff |= a[i] ^ b[i];
  return diff === 0;
}

function b64url(input: Buffer | string): string {
  const buf = Buffer.isBuffer(input) ? input : Buffer.from(input, 'utf8');
  return buf.toString('base64').replace(/=/g, '').replace(/\+/g, '-').replace(/\//g, '_');
}

function b64urlDecode(input: string): Buffer {
  const pad = input.length % 4 === 0 ? '' : '='.repeat(4 - (input.length % 4));
  return Buffer.from(input.replace(/-/g, '+').replace(/_/g, '/') + pad, 'base64');
}

function getSecret(): string {
  const secret = process.env.AUTH_JWT_SECRET;
  if (!secret || !secret.trim()) throw new Error('AUTH_JWT_SECRET must be configured');
  return secret;
}

export interface OfflineLeaseClaims {
  tenantId: string;
  profileId: string;
  deviceId: string;
  credentialVersion: number;
  exp: number;
}

export function issueOfflineLease(input: {
  tenantId: string;
  profileId: string;
  deviceId: string;
  credentialVersion: number;
  ttlMs?: number;
}): { token: string; expiresAt: string } {
  const exp = Date.now() + (input.ttlMs ?? DEFAULT_OFFLINE_LEASE_TTL_MS);
  const payload: OfflineLeaseClaims = {
    tenantId: input.tenantId,
    profileId: input.profileId,
    deviceId: input.deviceId,
    credentialVersion: input.credentialVersion,
    exp,
  };
  const body = b64url(JSON.stringify(payload));
  const sig = createHmac('sha256', getSecret()).update(body).digest();
  return { token: `${body}.${b64url(sig)}`, expiresAt: new Date(exp).toISOString() };
}

export function verifyOfflineLease(token: string): OfflineLeaseClaims | null {
  const parts = token.split('.');
  if (parts.length !== 2) return null;
  const [body, sigPart] = parts;
  let expected: Buffer;
  try {
    expected = createHmac('sha256', getSecret()).update(body).digest();
  } catch {
    return null;
  }
  let actual: Buffer;
  try {
    actual = b64urlDecode(sigPart);
  } catch {
    return null;
  }
  if (actual.length !== expected.length || !timingSafeEqualBytes(actual, expected)) return null;
  try {
    const payload = JSON.parse(b64urlDecode(body).toString('utf8')) as OfflineLeaseClaims;
    if (!payload?.tenantId || !payload?.profileId || !payload?.deviceId) return null;
    if (!Number.isFinite(payload.exp) || payload.exp <= Date.now()) return null;
    return payload;
  } catch {
    return null;
  }
}
