export type AdminTicketTransaction = {
  get<T>(key: string): Promise<T | undefined>;
  delete(key: string): Promise<boolean>;
};

export type AdminLiveAccess = {
  isSuperAdmin: boolean;
  permissions: string[];
};

export type StoredAdminTicket = AdminLiveAccess & { expiresAt: number };

export type AdminTicketStorage = {
  put(key: string, value: StoredAdminTicket): Promise<void>;
  transaction<T>(callback: (storage: AdminTicketTransaction) => Promise<T>): Promise<T>;
};

const TICKET_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export async function registerAdminLiveTicket(
  storage: Pick<AdminTicketStorage, 'put'>,
  ticket: unknown,
  expiresIn: unknown,
  now = Date.now(),
  access: AdminLiveAccess = { isSuperAdmin: false, permissions: [] },
): Promise<boolean> {
  if (
    typeof ticket !== 'string' ||
    !TICKET_PATTERN.test(ticket) ||
    typeof expiresIn !== 'number' ||
    !Number.isInteger(expiresIn) ||
    expiresIn < 1 ||
    expiresIn > 60 ||
    typeof access.isSuperAdmin !== 'boolean' ||
    !Array.isArray(access.permissions) ||
    access.permissions.length > 100 ||
    access.permissions.some((permission) =>
      typeof permission !== 'string' ||
      !/^[a-z][a-z0-9_-]*:[a-z][a-z0-9_-]*$/.test(permission),
    )
  ) {
    return false;
  }
  await storage.put(await storageKey(ticket), {
    expiresAt: now + expiresIn * 1000,
    isSuperAdmin: access.isSuperAdmin,
    permissions: [...new Set(access.permissions)],
  });
  return true;
}

export async function consumeAdminLiveTicket(
  storage: Pick<AdminTicketStorage, 'transaction'>,
  ticket: string,
  now = Date.now(),
): Promise<AdminLiveAccess | null> {
  if (!TICKET_PATTERN.test(ticket)) return null;
  const key = await storageKey(ticket);
  return storage.transaction(async (transaction) => {
    const stored = await transaction.get<StoredAdminTicket>(key);
    await transaction.delete(key);
    if (
      !stored ||
      !Number.isFinite(stored.expiresAt) ||
      stored.expiresAt <= now ||
      typeof stored.isSuperAdmin !== 'boolean' ||
      !Array.isArray(stored.permissions)
    ) return null;
    return {
      isSuperAdmin: stored.isSuperAdmin,
      permissions: stored.permissions.filter((permission): permission is string =>
        typeof permission === 'string' &&
        /^[a-z][a-z0-9_-]*:[a-z][a-z0-9_-]*$/.test(permission),
      ),
    };
  });
}

async function storageKey(ticket: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(ticket)),
  );
  const hash = Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `admin-ws-ticket:${hash}`;
}
