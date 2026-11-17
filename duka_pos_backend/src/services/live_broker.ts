import type { WebSocket } from 'ws';

export type LiveClient = {
  socket: WebSocket;
  tenantId: string;
};

const clients = new Set<LiveClient>();

export function addLiveClient(client: LiveClient): void {
  clients.add(client);
}

export function removeLiveClient(client: LiveClient): void {
  clients.delete(client);
}

/**
 * Send a signal only to tills in the changed shop. The payload is deliberately
 * a signal, not ledger data: each client re-reads its normal authenticated
 * endpoint, keeping HTTP responses the source of truth and making reconnects
 * safe.
 */
export function broadcastTenantChange(
  tenantId: string,
  reasons: string[] = [],
): void {
  const message = JSON.stringify({
    type: 'snapshot',
    reasons,
    at: new Date().toISOString(),
  });
  for (const client of clients) {
    if (client.tenantId !== tenantId) continue;
    if (client.socket.readyState !== client.socket.OPEN) continue;
    client.socket.send(message);
  }
}

export function broadcastAll(message: unknown): void {
  const encoded = JSON.stringify(message);
  for (const client of clients) {
    if (client.socket.readyState === client.socket.OPEN) client.socket.send(encoded);
  }
}

