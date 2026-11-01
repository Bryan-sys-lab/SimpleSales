import bcrypt from 'bcryptjs';

const ROUNDS = 10;

export async function hashPassword(password: string): Promise<string> {
  return bcrypt.hash(password, ROUNDS);
}

export async function verifyPassword(password: string, hash: string): Promise<boolean> {
  if (!hash) return false;
  try {
    return await bcrypt.compare(password, hash);
  } catch {
    return false;
  }
}

export function isSixDigitPassword(value: unknown): value is string {
  return typeof value === 'string' && /^\d{6}$/.test(value);
}
