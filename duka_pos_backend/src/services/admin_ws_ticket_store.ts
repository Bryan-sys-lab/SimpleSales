export type AdminTicketTransaction = {
  get<T>(key: string): Promise<T | undefined>;
  delete(key: string): Promise<boolean>;
};

export type AdminTicketStorage = {
  put(key: string, value: number): Promise<void>;
  transaction<T>(callback: (storage: AdminTicketTransaction) => Promise<T>): Promise<T>;
};

const TICKET_PATTERN = /^[A-Za-z0-9_-]{43}$/;

export async function registerAdminLiveTicket(
  storage: Pick<AdminTicketStorage, 'put'>,
  ticket: unknown,
  expiresIn: unknown,
  now = Date.now(),
): Promise<boolean> {
  if (
    typeof ticket !== 'string' ||
    !TICKET_PATTERN.test(ticket) ||
    typeof expiresIn !== 'number' ||
    !Number.isInteger(expiresIn) ||
    expiresIn < 1 ||
    expiresIn > 60
  ) {
    return false;
  }
  await storage.put(await storageKey(ticket), now + expiresIn * 1000);
  return true;
}

export async function consumeAdminLiveTicket(
  storage: Pick<AdminTicketStorage, 'transaction'>,
  ticket: string,
  now = Date.now(),
): Promise<boolean> {
  if (!TICKET_PATTERN.test(ticket)) return false;
  const key = await storageKey(ticket);
  return storage.transaction(async (transaction) => {
    const expiresAt = await transaction.get<number>(key);
    await transaction.delete(key);
    return typeof expiresAt === 'number' && expiresAt > now;
  });
}

async function storageKey(ticket: string): Promise<string> {
  const digest = new Uint8Array(
    await crypto.subtle.digest('SHA-256', new TextEncoder().encode(ticket)),
  );
  const hash = Array.from(digest, (byte) => byte.toString(16).padStart(2, '0')).join('');
  return `admin-ws-ticket:${hash}`;
}
