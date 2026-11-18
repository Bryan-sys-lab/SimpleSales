import type { WebSocket } from 'ws';

export type AdminLiveClient = { socket: WebSocket };

const clients = new Set<AdminLiveClient>();

export function addAdminLiveClient(client: AdminLiveClient): void {
  clients.add(client);
}

export function removeAdminLiveClient(client: AdminLiveClient): void {
  clients.delete(client);
}

export function broadcastAdmin(message: unknown): void {
  const encoded = JSON.stringify(message);
  for (const client of clients) {
    if (client.socket.readyState === client.socket.OPEN) {
      client.socket.send(encoded);
    }
  }
}
