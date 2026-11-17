import { describe, expect, it } from 'vitest';

import { readableTenantId } from '../lib/tenant_id';

describe('readable tenant ids', () => {
  it('includes normalized owner and shop names plus a short random suffix', () => {
    const id = readableTenantId('Élodie Mwangi', 'Mama & Sons Duka');
    expect(id).toMatch(/^elodie-mwangi-mama-sons-duka-\d{4}$/);
  });

  it('falls back to readable labels when names contain no identifier characters', () => {
    expect(readableTenantId('!!!', '???')).toMatch(/^owner-shop-\d{4}$/);
  });
});
