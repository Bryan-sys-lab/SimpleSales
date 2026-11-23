import crypto from 'node:crypto';

export type AdminLiveAccess = {
  isSuperAdmin: boolean;
  permissions: string[];
};

const tickets = new Map<string, { expiresAt: number; access: AdminLiveAccess }>();
const TTL_MS = 30_000;

export function issueAdminWebSocketTicket(access: AdminLiveAccess): string {
  const now = Date.now();
  for (const [ticket, value] of tickets) if (value.expiresAt <= now) tickets.delete(ticket);
  const ticket = crypto.randomBytes(32).toString('base64url');
  tickets.set(ticket, {
    expiresAt: now + TTL_MS,
    access: {
      isSuperAdmin: access.isSuperAdmin,
      permissions: [...new Set(access.permissions)],
    },
  });
  return ticket;
}

export function consumeAdminWebSocketTicket(ticket: string): AdminLiveAccess | null {
  const value = tickets.get(ticket);
  tickets.delete(ticket);
  return value && value.expiresAt > Date.now() ? value.access : null;
}
