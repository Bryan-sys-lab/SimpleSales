import { describe, expect, it } from 'vitest';
import {
  consumeAdminLiveTicket,
  registerAdminLiveTicket,
  type AdminTicketStorage,
} from '../services/admin_ws_ticket_store';

function createStorage(): AdminTicketStorage {
  const entries = new Map<string, number>();
  return {
    put: async (key, value) => { entries.set(key, value); },
    transaction: async (callback) => callback({
      get: async <T>(key: string) => entries.get(key) as T | undefined,
      delete: async (key) => entries.delete(key),
    }),
  };
}

describe('admin live ticket storage', () => {
  it('accepts a registered ticket only once', async () => {
    const storage = createStorage();
    const ticket = 'A'.repeat(43);

    expect(await registerAdminLiveTicket(storage, ticket, 30, 1000)).toBe(true);
    expect(await consumeAdminLiveTicket(storage, ticket, 2000)).toBe(true);
    expect(await consumeAdminLiveTicket(storage, ticket, 2000)).toBe(false);
  });

  it('rejects malformed or expired tickets', async () => {
    const storage = createStorage();

    expect(await registerAdminLiveTicket(storage, 'not-a-ticket', 30)).toBe(false);
    expect(await registerAdminLiveTicket(storage, 'B'.repeat(43), 61)).toBe(false);
    expect(await registerAdminLiveTicket(storage, 'B'.repeat(43), 1, 1000)).toBe(true);
    expect(await consumeAdminLiveTicket(storage, 'B'.repeat(43), 2000)).toBe(false);
  });
});
