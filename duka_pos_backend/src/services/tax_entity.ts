import { createCipheriv, randomBytes } from 'node:crypto';

const keyBytes = (): Buffer => {
  const raw = process.env.TAX_ENTITY_ENCRYPTION_KEY;
  if (!raw) throw new Error('TAX_ENTITY_ENCRYPTION_KEY is not configured');
  const key = Buffer.from(raw, 'base64');
  if (key.length !== 32) throw new Error('TAX_ENTITY_ENCRYPTION_KEY must be 32-byte base64');
  return key;
};

/** Seals a KRA PIN; the API never persists or returns the plaintext value. */
export function encryptTaxSecret(value: string): string {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', keyBytes(), iv);
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return Buffer.concat([iv, tag, ciphertext]).toString('base64');
}

export function lastFour(value: string): string {
  return value.slice(-4);
}
