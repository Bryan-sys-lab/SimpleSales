import { randomInt } from 'node:crypto';

/**
 * Creates the human-facing tenant/account identifier shown to shop owners.
 *
 * Existing tenants keep their current ids. New ids are intentionally readable
 * enough to dictate over the phone while retaining a random suffix so two
 * owners can use the same name without colliding.
 */
export function readableTenantId(ownerName: string, shopName: string): string {
  const slug = (value: string, fallback: string): string => {
    const normalized = value
      .normalize('NFKD')
      .replace(/[\u0300-\u036f]/g, '')
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-+|-+$/g, '')
      .slice(0, 24);
    return normalized || fallback;
  };

  return `${slug(ownerName, 'owner')}-${slug(shopName, 'shop')}-${randomInt(1000, 10000)}`;
}
