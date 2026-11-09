import { describe, expect, it } from 'vitest';
import { encryptTaxSecret, lastFour } from '../services/tax_entity';

describe('tax entity secret boundary', () => {
  it('stores a PIN as authenticated ciphertext, never plaintext', () => {
    const previous = process.env.TAX_ENTITY_ENCRYPTION_KEY;
    process.env.TAX_ENTITY_ENCRYPTION_KEY = Buffer.alloc(32, 7).toString('base64');
    try {
      const ciphertext = encryptTaxSecret('P051234567X');
      expect(ciphertext).not.toContain('P051234567X');
      expect(Buffer.from(ciphertext, 'base64').length).toBeGreaterThan(27);
      expect(lastFour('P051234567X')).toBe('567X');
    } finally {
      if (previous === undefined) delete process.env.TAX_ENTITY_ENCRYPTION_KEY;
      else process.env.TAX_ENTITY_ENCRYPTION_KEY = previous;
    }
  });

  it('fails closed when the deployment key is absent', () => {
    const previous = process.env.TAX_ENTITY_ENCRYPTION_KEY;
    delete process.env.TAX_ENTITY_ENCRYPTION_KEY;
    try {
      expect(() => encryptTaxSecret('P051234567X')).toThrow('not configured');
    } finally {
      if (previous !== undefined) process.env.TAX_ENTITY_ENCRYPTION_KEY = previous;
    }
  });
});
