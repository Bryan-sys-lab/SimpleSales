import crypto from 'node:crypto';

const tickets = new Map<string, number>();
const TTL_MS = 30_000;

export function issueAdminWebSocketTicket(): string {
  const now = Date.now();
  for (const [ticket, expiresAt] of tickets) if (expiresAt <= now) tickets.delete(ticket);
  const ticket = crypto.randomBytes(32).toString('base64url');
  tickets.set(ticket, now + TTL_MS);
  return ticket;
}

export function consumeAdminWebSocketTicket(ticket: string): boolean {
  const expiresAt = tickets.get(ticket);
  tickets.delete(ticket);
  return Boolean(expiresAt && expiresAt > Date.now());
}
